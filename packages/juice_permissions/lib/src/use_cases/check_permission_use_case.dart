import 'package:juice/juice.dart';

import '../permissions_bloc.dart';
import '../permissions_events.dart';
import 'permissions_emit_mixin.dart';

/// Handles [CheckPermissionEvent] — read status without prompting.
class CheckPermissionUseCase
    extends BlocUseCase<PermissionsBloc, CheckPermissionEvent>
    with PermissionsEmit<CheckPermissionEvent> {
  @override
  Future<void> execute(CheckPermissionEvent event) async {
    final status = await bloc.provider.status(event.permission);
    emitStatuses({event.permission: status});
  }
}
