import 'package:juice/juice.dart';

import 'lifecycle_config.dart';
import 'lifecycle_events.dart';
import 'lifecycle_provider.dart';
import 'lifecycle_state.dart';
import 'use_cases/initialize_lifecycle_use_case.dart';
import 'use_cases/lifecycle_changed_use_case.dart';

/// Bloc that owns the app's lifecycle phase (foreground/background/resume).
///
/// Reads lifecycle through a [LifecycleProvider] (the vendor seam), so it is
/// testable without a real `WidgetsBinding`: inject a fake and drive its stream.
///
/// ```dart
/// final lifecycle = LifecycleBloc.withConfig(LifecycleConfig());
/// // ... react to state.isForeground / state.resumedFromBackground
/// ```
class LifecycleBloc extends JuiceBloc<LifecycleState> {
  LifecycleConfig? _config;

  LifecycleBloc()
      : super(
          LifecycleState.initial,
          [
            () => UseCaseBuilder(
                  typeOfEvent: InitializeLifecycleEvent,
                  useCaseGenerator: () => InitializeLifecycleUseCase(),
                  concurrency: EventConcurrency.droppable,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: LifecycleChangedEvent,
                  useCaseGenerator: () => LifecycleChangedUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
          ],
        );

  /// Create and initialize in one step.
  factory LifecycleBloc.withConfig(LifecycleConfig config) {
    final bloc = LifecycleBloc();
    bloc.send(InitializeLifecycleEvent(config: config));
    return bloc;
  }

  /// The active provider. Valid after initialization.
  LifecycleProvider get provider => config.provider;

  /// The config [InitializeLifecycleEvent] applied. Throws before that.
  LifecycleConfig get config =>
      _config ??
      (throw StateError(
          'LifecycleBloc is not initialized: send InitializeLifecycleEvent '
          '(or use LifecycleBloc.withConfig) first'));

  /// Store config during initialization.
  void configure(LifecycleConfig config) => _config = config;

  /// Subscribe to provider changes. The bloc owns the binding: a second
  /// start replaces the first, and close cancels it before the use cases
  /// close. A stream error goes to the bloc's error handler; the binding
  /// keeps listening, as the old subscription did.
  void startListening() {
    bindStream<AppLifecycle>(
      provider.changes,
      (phase) => send(LifecycleChangedEvent(phase)),
      key: _changesKey,
      cancelOnError: false,
    );
  }

  static const _changesKey = 'changes';

  // Memoized like the core's close(): a second caller awaits the first
  // teardown, so the provider is disposed once. `super.close()` is invoked
  // here (the core requires it) and awaited inside.
  @override
  Future<void> close() => _closeOnce ??= _close(super.close());
  Future<void>? _closeOnce;

  Future<void> _close(Future<void> closing) async {
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
          'LifecycleProvider dispose failed', error, stackTrace,
          context: {'type': 'bloc_error', 'bloc': 'LifecycleBloc'});
    }
  }
}
