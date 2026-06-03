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
  late LifecycleConfig _config;
  StreamSubscription<AppLifecycle>? _subscription;

  LifecycleBloc()
      : super(
          LifecycleState.initial,
          [
            () => UseCaseBuilder(
                  typeOfEvent: InitializeLifecycleEvent,
                  useCaseGenerator: () => InitializeLifecycleUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: LifecycleChangedEvent,
                  useCaseGenerator: () => LifecycleChangedUseCase(),
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
  LifecycleProvider get provider => _config.provider;

  /// Store config during initialization.
  void configure(LifecycleConfig config) => _config = config;

  /// Subscribe to provider changes.
  void startListening() {
    _subscription = provider.changes.listen((phase) {
      if (!isClosed) send(LifecycleChangedEvent(phase));
    });
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    try {
      await _config.provider.dispose();
    } catch (_) {
      // Provider may never have been configured; ignore.
    }
    await super.close();
  }
}
