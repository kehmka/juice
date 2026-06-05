import 'package:juice/juice.dart';

import '../location_bloc.dart';
import '../location_events.dart';
import '../location_state.dart';

/// Handles [SetPermissionStatusEvent] — record whether reading is allowed.
class SetPermissionStatusUseCase
    extends BlocUseCase<LocationBloc, SetPermissionStatusEvent> {
  @override
  Future<void> execute(SetPermissionStatusEvent event) async {
    if (event.granted == bloc.state.permissionGranted) return;
    emitUpdate(
      newState: bloc.state.copyWith(permissionGranted: event.granted),
      groupsToRebuild: {LocationGroups.permission},
    );
  }
}
