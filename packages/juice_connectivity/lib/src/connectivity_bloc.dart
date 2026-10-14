import 'package:juice/juice.dart';

import 'connectivity_config.dart';
import 'connectivity_events.dart';
import 'connectivity_provider.dart';
import 'connectivity_state.dart';
import 'use_cases/check_connectivity_use_case.dart';
import 'use_cases/connectivity_changed_use_case.dart';
import 'use_cases/initialize_connectivity_use_case.dart';

/// Bloc that owns the device's network reachability state.
///
/// Reads connectivity through a [ConnectivityProvider] (the vendor seam), so it
/// is fully testable without a device: inject a fake provider and drive its
/// stream.
///
/// ```dart
/// final bloc = ConnectivityBloc.withConfig(ConnectivityConfig());
/// // ... later
/// if (bloc.state.isOnline) { /* ... */ }
/// ```
class ConnectivityBloc extends JuiceBloc<ConnectivityState> {
  ConnectivityConfig? _config;
  Timer? _debounce;

  ConnectivityBloc()
      : super(
          ConnectivityState.initial,
          [
            () => UseCaseBuilder(
                  typeOfEvent: InitializeConnectivityEvent,
                  useCaseGenerator: () => InitializeConnectivityUseCase(),
                  // A second initialization would replace the config while
                  // the first provider check is in flight.
                  concurrency: EventConcurrency.droppable,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: ConnectivityChangedEvent,
                  useCaseGenerator: () => ConnectivityChangedUseCase(),
                  // Each reading compares against and conditionally replaces
                  // shared state. Keep that transaction in arrival order even
                  // if this use case later gains an await.
                  concurrency: EventConcurrency.sequential,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: CheckConnectivityEvent,
                  useCaseGenerator: () => CheckConnectivityUseCase(),
                  // Concurrent checks ask the same provider for the same
                  // present-tense answer; one in-flight read is sufficient.
                  concurrency: EventConcurrency.droppable,
                ),
          ],
        );

  /// Create and initialize in one step.
  factory ConnectivityBloc.withConfig(ConnectivityConfig config) {
    final bloc = ConnectivityBloc();
    bloc.send(InitializeConnectivityEvent(config: config));
    return bloc;
  }

  /// The active provider. Valid after initialization.
  ConnectivityProvider get provider => config.provider;

  /// The config [InitializeConnectivityEvent] applied. Throws before that.
  ConnectivityConfig get config =>
      _config ??
      (throw StateError('ConnectivityBloc is not initialized: send '
          'InitializeConnectivityEvent (or use ConnectivityBloc.withConfig) '
          'first'));

  /// Store the config during initialization. One per bloc: a second
  /// `InitializeConnectivityEvent` after the first completed is refused here (the
  /// first provider stays owned and live), loudly, through the use case's
  /// error path.
  void configure(ConnectivityConfig config) {
    if (_config != null) {
      throw StateError(
          'ConnectivityBloc is already initialized; it owns one config for its life');
    }
    _config = config;
  }

  /// Subscribe to provider changes, debounced to absorb network flapping.
  /// The bloc owns the binding: a second start replaces the first, and
  /// close cancels it before the use cases close. A stream error goes to
  /// the bloc's error handler; the binding keeps listening, as the old
  /// subscription did.
  void startListening() {
    bindStream<ConnectivitySnapshot>(
      provider.changes,
      (snapshot) {
        _debounce?.cancel();
        _debounce = Timer(config.debounce, () {
          if (!isClosing) send(ConnectivityChangedEvent(snapshot));
        });
      },
      key: _changesKey,
      cancelOnError: false,
    );
  }

  static const _changesKey = 'changes';

  /// Manually re-read current connectivity.
  void check() => send(CheckConnectivityEvent());

  // Memoized like the core's close(): a second caller awaits the first
  // teardown, so the provider is disposed once. `super.close()` is invoked
  // here (the core requires it) and awaited inside.
  @override
  Future<void> close() => _closeOnce ??= _close(super.close());
  Future<void>? _closeOnce;

  Future<void> _close(Future<void> closing) async {
    _debounce?.cancel();
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
          'ConnectivityProvider dispose failed', error, stackTrace,
          context: {'type': 'bloc_error', 'bloc': 'ConnectivityBloc'});
    }
  }
}
