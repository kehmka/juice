import 'package:juice/juice.dart';

import '../notifications_bloc.dart';
import '../notifications_events.dart';
import '../notifications_state.dart';

/// Handles [SetPermissionStatusEvent] — record whether posting is allowed.
class SetPermissionStatusUseCase
    extends BlocUseCase<NotificationsBloc, SetPermissionStatusEvent> {
  @override
  Future<void> execute(SetPermissionStatusEvent event) async {
    if (event.granted == bloc.state.permissionGranted) return;
    emitUpdate(
      newState: bloc.state.copyWith(permissionGranted: event.granted),
      groupsToRebuild: {NotificationsGroups.permission},
    );
  }
}
