/// Lifecycle of one item's upload.
enum UploadStatus { queued, uploading, completed, failed, cancelled }

/// Immutable upload state for one media item.
class UploadState {
  final String itemId;
  final UploadStatus status;

  /// Progress in `0.0..1.0`.
  final double progress;

  /// Remote URL/identifier once completed.
  final String? remoteUrl;

  /// Error message if failed.
  final String? error;

  const UploadState({
    required this.itemId,
    this.status = UploadStatus.queued,
    this.progress = 0,
    this.remoteUrl,
    this.error,
  });

  /// State for a remote-origin item — already hosted, so it starts `completed`.
  const UploadState.remote(this.itemId, String? url)
      : status = UploadStatus.completed,
        progress = 1,
        remoteUrl = url,
        error = null;

  bool get isActive => status == UploadStatus.uploading;
  bool get isDone => status == UploadStatus.completed;

  UploadState copyWith({
    UploadStatus? status,
    double? progress,
    Object? remoteUrl = _unset,
    Object? error = _unset,
  }) {
    return UploadState(
      itemId: itemId,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      remoteUrl: identical(remoteUrl, _unset) ? this.remoteUrl : remoteUrl as String?,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }

  @override
  String toString() =>
      'UploadState($itemId, $status, ${(progress * 100).round()}%)';
}

const Object _unset = Object();
