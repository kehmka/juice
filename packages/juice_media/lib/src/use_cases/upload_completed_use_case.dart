import 'package:juice/juice.dart';

import '../media_bloc.dart';
import '../media_events.dart';
import '../media_state.dart';
import '../upload_state.dart';

/// Handles [UploadCompletedEvent] — mark done with the remote URL.
class UploadCompletedUseCase
    extends BlocUseCase<MediaBloc, UploadCompletedEvent> {
  @override
  Future<void> execute(UploadCompletedEvent event) async {
    bloc.cleanupUpload(event.id);

    final upload = bloc.state.uploads[event.id];
    if (upload == null) return;

    emitUpdate(
      newState: bloc.state.copyWith(
        uploads: {
          ...bloc.state.uploads,
          event.id: upload.copyWith(
            status: UploadStatus.completed,
            progress: 1,
            remoteUrl: event.remoteUrl,
            error: null,
          ),
        },
      ),
      groupsToRebuild: {MediaGroups.item(event.id), MediaGroups.any},
    );
  }
}
