import 'package:juice/juice.dart';

import '../media_bloc.dart';
import '../media_events.dart';
import '../media_state.dart';
import '../upload_state.dart';

/// Handles [UploadItemEvent] — start one item's upload.
///
/// Fails loudly if no uploader is configured (never a silent no-op).
class UploadItemUseCase extends BlocUseCase<MediaBloc, UploadItemEvent> {
  @override
  Future<void> execute(UploadItemEvent event) async {
    final item =
        bloc.state.items.where((i) => i.id == event.id).firstOrNull;
    if (item == null) return;

    // Already uploading or done — don't restart.
    final existing = bloc.state.uploads[event.id];
    if (existing != null &&
        (existing.status == UploadStatus.uploading ||
            existing.status == UploadStatus.completed)) {
      return;
    }

    if (bloc.uploader == null) {
      emitFailure(
        newState: bloc.state.copyWith(
          lastError: 'No uploader configured',
          uploads: {
            ...bloc.state.uploads,
            event.id: UploadState(
              itemId: event.id,
              status: UploadStatus.failed,
              error: 'No uploader configured',
            ),
          },
        ),
        groupsToRebuild: {MediaGroups.item(event.id), MediaGroups.error},
        error: StateError('MediaBloc.upload() with no uploader configured'),
      );
      return;
    }

    emitUpdate(
      newState: bloc.state.copyWith(
        uploads: {
          ...bloc.state.uploads,
          event.id: UploadState(
              itemId: event.id, status: UploadStatus.uploading, progress: 0),
        },
      ),
      groupsToRebuild: {MediaGroups.item(event.id), MediaGroups.any},
    );

    bloc.beginUpload(item);
  }
}
