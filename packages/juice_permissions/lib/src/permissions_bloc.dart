import 'package:juice/juice.dart';

import 'permission_provider.dart';
import 'permissions_config.dart';
import 'permissions_events.dart';
import 'permissions_state.dart';
import 'use_cases/check_permission_use_case.dart';
import 'use_cases/initialize_permissions_use_case.dart';
import 'use_cases/open_app_settings_use_case.dart';
import 'use_cases/request_permission_use_case.dart';
import 'use_cases/request_permissions_use_case.dart';

/// Bloc that owns the grant-state machine for runtime permissions.
///
/// Reads and requests permissions through a [PermissionProvider] (the vendor
/// seam), so it is fully testable without a device: inject a fake provider.
///
/// ```dart
/// final permissions = PermissionsBloc.withConfig(PermissionsConfig());
/// permissions.request(JuicePermission.camera);
/// // ... later
/// if (permissions.state.isUsable(JuicePermission.camera)) { /* open camera */ }
/// ```
class PermissionsBloc extends JuiceBloc<PermissionsState> {
  late PermissionsConfig _config;

  /// Per-permission singleflight: concurrent requests for the same permission
  /// share one prompt. Authoritative for coalescing; `state.inFlight` mirrors
  /// it for the UI.
  final Map<JuicePermission, Completer<PermissionStatus>> requestsInFlight = {};

  PermissionsBloc()
      : super(
          PermissionsState.initial,
          [
            () => UseCaseBuilder(
                  typeOfEvent: InitializePermissionsEvent,
                  useCaseGenerator: () => InitializePermissionsUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: CheckPermissionEvent,
                  useCaseGenerator: () => CheckPermissionUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: RequestPermissionEvent,
                  useCaseGenerator: () => RequestPermissionUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: RequestPermissionsEvent,
                  useCaseGenerator: () => RequestPermissionsUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: OpenAppSettingsEvent,
                  useCaseGenerator: () => OpenAppSettingsUseCase(),
                ),
          ],
        );

  /// Create and initialize in one step.
  factory PermissionsBloc.withConfig(PermissionsConfig config) {
    final bloc = PermissionsBloc();
    bloc.send(InitializePermissionsEvent(config: config));
    return bloc;
  }

  /// The active provider. Valid after initialization.
  PermissionProvider get provider => _config.provider;

  /// Store config during initialization.
  void configure(PermissionsConfig config) => _config = config;

  // === Convenience ===

  /// Read a permission's status without prompting.
  void check(JuicePermission permission) =>
      send(CheckPermissionEvent(permission));

  /// Prompt for a permission.
  void request(JuicePermission permission) =>
      send(RequestPermissionEvent(permission));

  /// Prompt for several permissions at once.
  void requestAll(Set<JuicePermission> permissions) =>
      send(RequestPermissionsEvent(permissions));

  /// Open the OS app settings page.
  void openAppSettings() => send(OpenAppSettingsEvent());

  @override
  Future<void> close() async {
    try {
      await _config.provider.dispose();
    } catch (_) {
      // Provider may never have been configured; ignore.
    }
    await super.close();
  }
}
