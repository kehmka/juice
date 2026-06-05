import 'package:juice/juice.dart';

import '../media_bloc.dart';
import '../media_events.dart';
import '../media_state.dart';
import '../upload_state.dart';

/// Handles [UploadFailedEvent] — mark failed and surface the error loudly.
class UploadFailedUseCase extends BlocUseCase<MediaBloc, UploadFailedEvent> {
  @override
  Future<void> execute(UploadFailedEvent event) async {
    bloc.cleanupUpload(event.id);

    final upload = bloc.state.uploads[event.id];
    if (upload == null) return;

    emitFailure(
      newState: bloc.state.copyWith(
        uploads: {
          ...bloc.state.uploads,
          event.id: upload.copyWith(
            status: UploadStatus.failed,
            error: event.error.toString(),
          ),
        },
      ),
      groupsToRebuild: {MediaGroups.item(event.id), MediaGroups.error},
      error: event.error,
    );
  }
}
