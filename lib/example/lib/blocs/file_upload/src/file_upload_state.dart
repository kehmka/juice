import 'package:juice/juice.dart';

class FileUploadState extends BlocState {
  final String? filePath;
  final int fileSizeBytes;
  final int bytesUploaded;
  final String? error;
  final bool isUploading; // Added flag

  const FileUploadState({
    this.filePath,
    this.fileSizeBytes = 0,
    this.bytesUploaded = 0,
    this.error,
    this.isUploading = false, // Default to false
  });

  double get progress =>
      fileSizeBytes > 0 ? bytesUploaded / fileSizeBytes : 0.0;

  FileUploadState copyWith({
    String? filePath,
    int? fileSizeBytes,
    int? bytesUploaded,
    String? error,
    bool? isUploading, // Added to copyWith
  }) {
    return FileUploadState(
      filePath: filePath ?? this.filePath,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      bytesUploaded: bytesUploaded ?? this.bytesUploaded,
      error: error ?? this.error,
      isUploading: isUploading ?? this.isUploading, // Include in new instance
    );
  }
}
