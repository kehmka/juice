import 'package:juice/juice.dart';

import '../../file_upload.dart';

class FileUploadWidget extends StatefulWidget {
  const FileUploadWidget({super.key});

  @override
  State<StatefulWidget> createState() => FileUploadWidgetState();
}

class FileUploadWidgetState
    extends JuiceWidgetState<FileUploadBloc, FileUploadWidget> {
  FileUploadWidgetState({super.groups = const {"file_upload"}});

  UploadFileEvent? _currentUpload;

  String _formatDuration(Duration duration) {
    return '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    JuiceLoggerConfig.logger.log("Status is ${status.runtimeType}");
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Progress bar
            if (status is WaitingStatus || status is UpdatingStatus)
              LinearProgressIndicator(
                value: bloc.state.progress,
              ),

            const SizedBox(height: 16),

            // Timing information (from CancellableEvent)
            if (_currentUpload != null)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                      'Elapsed: ${_formatDuration(_currentUpload!.elapsedTime)}'),
                  if (_currentUpload!.timeRemaining != null)
                    Text(
                        'Timeout will occur in: ${_formatDuration(_currentUpload!.timeRemaining!)}'),
                ],
              ),

            const SizedBox(height: 16),

            // Status and controls
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Status text
                Expanded(
                  child: _buildStatusText(context, status),
                ),

                // Action buttons
                Row(
                  children: [
                    // Upload button - enabled when not uploading
                    ElevatedButton(
                      onPressed: bloc.state.isUploading
                          ? null
                          : () {
                              _currentUpload = bloc.sendCancellable(
                                UploadFileEvent(
                                  filePath: 'sample.txt',
                                  fileSizeBytes: 1024 * 1024, // 1MB
                                  timeout: const Duration(seconds: 30),
                                ),
                              );
                            },
                      child: const Text('Upload'),
                    ),

                    const SizedBox(width: 8),

                    // Cancel button - enabled during upload
                    OutlinedButton(
                      onPressed:
                          (status is WaitingStatus || status is UpdatingStatus)
                              ? () => _currentUpload?.cancel()
                              : null,
                      style: ButtonStyle(
                        foregroundColor: WidgetStateProperty.all(Colors.red),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusText(BuildContext context, StreamStatus status) {
    final state = bloc.state;

    if (status is CancelingStatus) {
      final event = status.event;
      if (event is UploadFileEvent && event.isTimedOut) {
        return Text(
          'Upload timed out',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.red,
              ),
        );
      }
      return Text(
        'Upload cancelled',
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.red,
            ),
      );
    }

    if (status is WaitingStatus || status is UpdatingStatus) {
      return Text(
        'Uploading... ${(state.progress * 100).toStringAsFixed(1)}%',
        style: Theme.of(context).textTheme.bodyLarge,
      );
    }

    if (state.error != null) {
      return Text(
        'Error: ${state.error}',
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.red,
            ),
      );
    }

    if (state.progress >= 1.0) {
      return Text(
        'Upload complete',
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.green,
            ),
      );
    }

    return const Text('Ready to upload');
  }

  @override
  bool onStateChange(StreamStatus status) {
    // Reset current upload when complete
    if (status is! WaitingStatus &&
        status is! UpdatingStatus &&
        status is! CancelingStatus) {
      _currentUpload = null;
    }
    return true;
  }
}
