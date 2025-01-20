import 'package:juice/juice.dart';

class UploadFileEvent extends CancellableEvent with TimeoutSupport {
  final String filePath;
  final int fileSizeBytes;

  UploadFileEvent({
    required this.filePath,
    required this.fileSizeBytes,
    Duration? timeout,
  }) {
    this.timeout = timeout;
  }
}
