import 'package:juice/juice.dart';

import 'permission_provider.dart';
import 'permissions_config.dart';

/// Base class for permission events.
abstract class PermissionsEvent extends EventBase {
  @override
  String toString() => runtimeType.toString();
}

/// Configure the provider and optionally pre-read a set of statuses.
class InitializePermissionsEvent extends PermissionsEvent {
  final PermissionsConfig config;
  InitializePermissionsEvent({required this.config});
}

/// Read a permission's status without prompting.
class CheckPermissionEvent extends PermissionsEvent {
  final JuicePermission permission;
  CheckPermissionEvent(this.permission);
}

/// Prompt the user for a permission (singleflight per permission).
class RequestPermissionEvent extends PermissionsEvent {
  final JuicePermission permission;
  RequestPermissionEvent(this.permission);
}

/// Prompt the user for several permissions at once.
class RequestPermissionsEvent extends PermissionsEvent {
  final Set<JuicePermission> permissions;
  RequestPermissionsEvent(this.permissions);
}

/// Open the app's system settings page (for permanently-denied permissions).
class OpenAppSettingsEvent extends PermissionsEvent {}
