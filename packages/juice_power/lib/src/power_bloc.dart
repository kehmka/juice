import 'package:juice/juice.dart';

import 'power_config.dart';
import 'power_events.dart';
import 'power_provider.dart';
import 'power_state.dart';
import 'use_cases/check_power_use_case.dart';
import 'use_cases/initialize_power_use_case.dart';
import 'use_cases/power_changed_use_case.dart';

/// Bloc that owns the device's power state — plugged in or not, how much
/// charge remains, and whether the OS power saver is on.
///
/// Reads power through a [PowerProvider] (the vendor seam), so it is fully
/// testable without a device: inject a fake provider and drive its stream.
///
/// ```dart
/// final power = PowerBloc.withConfig(PowerConfig());
/// // ... a bloc that does expensive work reacts to the edge:
/// StateRelay<PowerBloc, WellBloc, PowerState>(
///   toEvent: (_) => PauseWellEvent(),
///   when: (s) => s.oldState.isPluggedIn && !s.state.isPluggedIn,
/// );
/// ```
class PowerBloc extends JuiceBloc<PowerState> {
  PowerConfig? _config;
  Timer? _poll;

  PowerBloc()
      : super(
          PowerState.initial,
          [
            // A second initialization would replace the config while the
            // first provider check is in flight. droppable, not a
            // `_initialized` flag (juice >= 1.5.0).
            () => UseCaseBuilder(
                  typeOfEvent: InitializePowerEvent,
                  useCaseGenerator: () => InitializePowerUseCase(),
                  concurrency: EventConcurrency.droppable,
                ),
            // Mutates shared state by reading it, comparing, and emitting.
            // That is atomic TODAY only because execute() never awaits; one
            // await added later would silently reintroduce the
            // read-before-await race, and the symptom — an occasional dropped
            // power change — would be near-impossible to reproduce. sequential
            // makes the safety structural instead of incidental.
            () => UseCaseBuilder(
                  typeOfEvent: PowerChangedEvent,
                  useCaseGenerator: () => PowerChangedUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
            // A poll tick and a consumer's manual check can coincide; the
            // second platform read would be pure waste, since both would
            // report the same instant.
            () => UseCaseBuilder(
                  typeOfEvent: CheckPowerEvent,
                  useCaseGenerator: () => CheckPowerUseCase(),
                  concurrency: EventConcurrency.droppable,
                ),
          ],
        );

  /// Create and initialize in one step.
  factory PowerBloc.withConfig(PowerConfig config) {
    final bloc = PowerBloc();
    bloc.send(InitializePowerEvent(config: config));
    return bloc;
  }

  /// The active provider. Valid after initialization.
  PowerProvider get provider => config.provider;

  /// The config [InitializePowerEvent] applied. Throws before that.
  PowerConfig get config =>
      _config ??
      (throw StateError(
          'PowerBloc is not initialized: send InitializePowerEvent '
          '(or use PowerBloc.withConfig) first'));

  /// Store the config during initialization. One per bloc: a second
  /// `InitializePowerEvent` after the first completed is refused here (the
  /// first provider stays owned and live), loudly, through the use case's
  /// error path.
  void configure(PowerConfig config) {
    if (_config != null) {
      throw StateError(
          'PowerBloc is already initialized; it owns one config for its life');
    }
    _config = config;
  }

  /// Subscribe to provider changes.
  ///
  /// Undebounced, unlike connectivity: power does not flap. Plugging a cable in
  /// is a real, deliberate act, and delaying the news by half a second only
  /// makes a consumer resume expensive work later than it could have.
  ///
  /// The bloc owns the binding: a second start replaces the first, and
  /// close cancels it before the use cases close. A stream error goes to
  /// the bloc's error handler; the binding keeps listening, as the old
  /// subscription did.
  void startListening() {
    bindStream<PowerSnapshot>(
      provider.changes,
      (snapshot) => send(PowerChangedEvent(snapshot)),
      key: _changesKey,
      cancelOnError: false,
    );
  }

  static const _changesKey = 'changes';

  /// Begin re-reading the charge level on [PowerConfig.pollInterval].
  ///
  /// No-op when the interval is [Duration.zero].
  void startPolling() {
    _poll?.cancel();
    final interval = config.pollInterval;
    if (interval == Duration.zero) return;
    _poll = Timer.periodic(interval, (_) {
      if (!isClosing) send(CheckPowerEvent());
    });
  }

  /// Manually re-read the current power situation.
  void check() => send(CheckPowerEvent());

  // Memoized like the core's close(): a second caller awaits the first
  // teardown, so the provider is disposed once. `super.close()` is invoked
  // here (the core requires it) and awaited inside.
  @override
  Future<void> close() => _closeOnce ??= _close(super.close());
  Future<void>? _closeOnce;

  Future<void> _close(Future<void> closing) async {
    _poll?.cancel();
    // The bloc closes first: its changes binding is cancelled before the
    // provider it listens to is disposed. An uninitialized bloc has no
    // provider.
    await closing;
    final config = _config;
    if (config == null) return;
    try {
      await config.provider.dispose();
    } catch (error, stackTrace) {
      JuiceLoggerConfig.logger.logError(
          'PowerProvider dispose failed', error, stackTrace,
          context: {'type': 'bloc_error', 'bloc': 'PowerBloc'});
    }
  }
}
