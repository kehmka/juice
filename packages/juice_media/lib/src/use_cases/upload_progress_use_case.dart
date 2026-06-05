import 'package:juice/juice.dart';

import '../media_bloc.dart';
import '../media_events.dart';
import '../media_state.dart';

/// Handles [UploadProgressEvent] — record progress for one item.
///
/// Emits only that item's group, so other items' progress widgets don't rebuild.
class UploadProgressUseCase extends BlocUseCase<MediaBloc, UploadProgressEvent> {
  @override
  Future<void> execute(UploadProgressEvent event) async {
    final upload = bloc.state.uploads[event.id];
    if (upload == null) return;

    emitUpdate(
      newState: bloc.state.copyWith(
        uploads: {
          ...bloc.state.uploads,
          event.id: upload.copyWith(progress: event.progress),
        },
      ),
      groupsToRebuild: {MediaGroups.item(event.id)},
    );
  }
}
