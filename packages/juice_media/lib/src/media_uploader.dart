import 'media_item.dart';

/// A single in-flight upload — the seam's unit of progress and cancellation.
///
/// Mirrors how real upload clients work (e.g. Dio `onSendProgress` +
/// `CancelToken`): a progress stream, a result future, and a cancel.
abstract class MediaUpload {
  /// Upload progress in `0.0..1.0`.
  Stream<double> get progress;

  /// Completes with the remote URL (or identifier) on success; throws on
  /// failure.
  Future<String> get result;

  /// Abort the upload. [result] should complete with an error or never.
  void cancel();
}

/// Vendor seam for uploading media.
///
/// Injected (no universal default — every backend differs). Back it with your
/// API, S3, Firebase Storage, or `juice_network`'s FetchBloc. The bloc owns
/// *progress state*, never the transport.
abstract class MediaUploader {
  /// Begin uploading [item]. Returns a handle to track/cancel it.
  MediaUpload upload(MediaItem item);

  /// Release resources.
  Future<void> dispose();
}
