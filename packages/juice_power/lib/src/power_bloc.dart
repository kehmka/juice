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
  late PowerConfig _config;
  StreamSubscription<PowerSnapshot>? _subscription;
  Timer? _poll;

  PowerBloc()
      : super(
          PowerState.initial,
          [
            // Initializing twice would subscribe twice and start a second
            // poll timer, and the first timer's handle would be overwritten
            // beyond the reach of close() — a leak that outlives the bloc.
            // droppable, not a `_initialized` flag (juice >= 1.5.0).
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
  PowerProvider get provider => _config.provider;

  /// Store config during initialization.
  void configure(PowerConfig config) => _config = config;

  /// Subscribe to provider changes.
  ///
  /// Undebounced, unlike connectivity: power does not flap. Plugging a cable in
  /// is a real, deliberate act, and delaying the news by half a second only
  /// makes a consumer resume expensive work later than it could have.
  void startListening() {
    _subscription = provider.changes.listen((snapshot) {
      if (!isClosed) send(PowerChangedEvent(snapshot));
    });
  }

  /// Begin re-reading the charge level on [PowerConfig.pollInterval].
  ///
  /// No-op when the interval is [Duration.zero].
  void startPolling() {
    final interval = _config.pollInterval;
    if (interval == Duration.zero) return;
    _poll = Timer.periodic(interval, (_) {
      if (!isClosed) send(CheckPowerEvent());
    });
  }

  /// Manually re-read the current power situation.
  void check() => send(CheckPowerEvent());

  @override
  Future<void> close() async {
    _poll?.cancel();
    await _subscription?.cancel();
    try {
      await _config.provider.dispose();
    } catch (_) {
      // Provider may never have been configured; ignore.
    }
    await super.close();
  }
}
