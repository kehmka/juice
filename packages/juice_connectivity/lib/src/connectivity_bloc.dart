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
  late ConnectivityConfig _config;
  StreamSubscription<ConnectivitySnapshot>? _subscription;
  Timer? _debounce;

  ConnectivityBloc()
      : super(
          ConnectivityState.initial,
          [
            () => UseCaseBuilder(
                  typeOfEvent: InitializeConnectivityEvent,
                  useCaseGenerator: () => InitializeConnectivityUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: ConnectivityChangedEvent,
                  useCaseGenerator: () => ConnectivityChangedUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: CheckConnectivityEvent,
                  useCaseGenerator: () => CheckConnectivityUseCase(),
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
  ConnectivityProvider get provider => _config.provider;

  /// Store config during initialization.
  void configure(ConnectivityConfig config) => _config = config;

  /// Subscribe to provider changes, debounced to absorb network flapping.
  void startListening() {
    _subscription = provider.changes.listen((snapshot) {
      _debounce?.cancel();
      _debounce = Timer(_config.debounce, () {
        if (!isClosed) send(ConnectivityChangedEvent(snapshot));
      });
    });
  }

  /// Manually re-read current connectivity.
  void check() => send(CheckConnectivityEvent());

  @override
  Future<void> close() async {
    _debounce?.cancel();
    await _subscription?.cancel();
    try {
      await _config.provider.dispose();
    } catch (_) {
      // Provider may never have been configured; ignore.
    }
    await super.close();
  }
}
