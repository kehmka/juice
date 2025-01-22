import 'package:juice/juice.dart';
import '../../file_upload.dart';

class UploadFileUseCase extends BlocUseCase<FileUploadBloc, UploadFileEvent> {
  @override
  Future<void> execute(UploadFileEvent event) async {
    try {
      // Set initial state with isUploading = true
      final initialState = FileUploadState(
        filePath: event.filePath,
        fileSizeBytes: event.fileSizeBytes,
        isUploading: true, // Set to true when starting
      );

      // Start operation
      emitWaiting(groupsToRebuild: {"file_upload"}, newState: initialState);

      // Simulate chunked upload
      final int chunkSize = 1024 * 64; // 64KB chunks
      int bytesUploaded = 0;

      while (bytesUploaded < event.fileSizeBytes) {
        // Check cancellation
        if (event.isCancelled) {
          emitCancel(
            groupsToRebuild: {"file_upload"},
            newState: bloc.state.copyWith(
              bytesUploaded: bytesUploaded,
              isUploading: false, // Set to false when cancelled
            ),
          );
          return;
        }

        // Simulate network delay
        await Future.delayed(const Duration(milliseconds: 500));

        // Update progress
        bytesUploaded += chunkSize;
        if (bytesUploaded > event.fileSizeBytes) {
          bytesUploaded = event.fileSizeBytes;
        }

        emitUpdate(
          newState: bloc.state.copyWith(
            bytesUploaded: bytesUploaded,
            isUploading: true, // Maintain true during upload
          ),
        );
      }

      // Complete successfully if not cancelled
      if (!event.isCancelled) {
        emitUpdate(
          newState: bloc.state.copyWith(
            bytesUploaded: event.fileSizeBytes,
            isUploading: false, // Set to false when complete
          ),
        );
      }
    } catch (e) {
      emitFailure(
        newState: bloc.state.copyWith(
          error: e.toString(),
          isUploading: false, // Set to false on error
        ),
      );
    }
  }
}
