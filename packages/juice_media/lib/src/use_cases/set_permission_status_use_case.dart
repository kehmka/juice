import 'package:juice/juice.dart';

import '../media_bloc.dart';
import '../media_events.dart';
import '../media_state.dart';

/// Handles [SetPermissionStatusEvent] — record camera/photos access (deduped).
class SetPermissionStatusUseCase
    extends BlocUseCase<MediaBloc, SetPermissionStatusEvent> {
  @override
  Future<void> execute(SetPermissionStatusEvent event) async {
    if (event.granted == bloc.state.permissionGranted) return;
    emitUpdate(
      newState: bloc.state.copyWith(permissionGranted: event.granted),
      groupsToRebuild: {MediaGroups.permission},
    );
  }
}
