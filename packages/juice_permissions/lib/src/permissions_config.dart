import 'permission_provider.dart';
import 'providers/permission_handler_provider.dart';

/// Configuration for [PermissionsBloc].
class PermissionsConfig {
  /// The permission source. Defaults to [PermissionHandlerProvider].
  ///
  /// Pass a fake here in tests to drive grants without a device.
  final PermissionProvider provider;

  /// Permissions to read (without prompting) on initialization.
  final Set<JuicePermission> precheck;

  PermissionsConfig({
    PermissionProvider? provider,
    this.precheck = const {},
  }) : provider = provider ?? PermissionHandlerProvider();
}
