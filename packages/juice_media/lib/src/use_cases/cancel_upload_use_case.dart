import 'package:juice/juice.dart';

import '../media_bloc.dart';
import '../media_events.dart';
import '../media_state.dart';
import '../upload_state.dart';

/// Handles [CancelUploadEvent] — abort an in-flight upload.
class CancelUploadUseCase extends BlocUseCase<MediaBloc, CancelUploadEvent> {
  @override
  Future<void> execute(CancelUploadEvent event) async {
    if (!bloc.isUploadActive(event.id)) return;

    bloc.cancelActiveUpload(event.id);

    final upload = bloc.state.uploads[event.id];
    if (upload == null) return;

    emitUpdate(
      newState: bloc.state.copyWith(
        uploads: {
          ...bloc.state.uploads,
          event.id: upload.copyWith(status: UploadStatus.cancelled),
        },
      ),
      groupsToRebuild: {MediaGroups.item(event.id), MediaGroups.any},
    );
  }
}
