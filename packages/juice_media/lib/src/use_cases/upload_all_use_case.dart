import 'package:juice/juice.dart';

import '../media_bloc.dart';
import '../media_events.dart';
import '../upload_state.dart';

/// Handles [UploadAllEvent] — upload every item not already uploading/completed.
class UploadAllUseCase extends BlocUseCase<MediaBloc, UploadAllEvent> {
  @override
  Future<void> execute(UploadAllEvent event) async {
    for (final item in bloc.state.items) {
      final status = bloc.state.uploads[item.id]?.status;
      if (status == UploadStatus.uploading ||
          status == UploadStatus.completed) {
        continue;
      }
      bloc.send(UploadItemEvent(item.id));
    }
  }
}
