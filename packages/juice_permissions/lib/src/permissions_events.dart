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

/// Prompt the user for a permission (singleflight per permission: a
/// request arriving while one for the SAME permission is prompting joins
/// it, and gets its answer).
///
/// A result event: `await bloc.sendForResult(RequestPermissionEvent(p),
/// timeout: …)` is the status the user left the permission in. It throws
/// what the provider threw.
///
/// The wait is on a PERSON answering the OS prompt: give it a timeout sized
/// to that (`sendForResult` waits 30 seconds unless told otherwise, then
/// throws `TimeoutException` while the prompt is still on screen; the
/// answer then lands in state only).
class RequestPermissionEvent extends ResultEvent<PermissionStatus>
    implements PermissionsEvent {
  final JuicePermission permission;
  RequestPermissionEvent(this.permission);

  @override
  String toString() => runtimeType.toString();
}

/// Prompt the user for several permissions at once.
///
/// A result event: `await bloc.sendForResult(RequestPermissionsEvent(ps),
/// timeout: …)` is the status of each permission asked for (empty for an
/// empty set). It throws what the provider threw. As for
/// [RequestPermissionEvent], size the timeout to a person answering
/// prompts.
class RequestPermissionsEvent
    extends ResultEvent<Map<JuicePermission, PermissionStatus>>
    implements PermissionsEvent {
  final Set<JuicePermission> permissions;
  RequestPermissionsEvent(this.permissions);

  @override
  String toString() => runtimeType.toString();
}

/// Open the app's system settings page (for permanently-denied permissions).
class OpenAppSettingsEvent extends PermissionsEvent {}
