import 'dart:typed_data';

/// Kind of media an item holds.
enum MediaKind { image, video }

/// Where to acquire media from.
enum MediaPickMode { gallery, camera }

/// A request to acquire media.
class MediaRequest {
  final MediaPickMode mode;
  final MediaKind kind;

  /// Allow selecting multiple items (gallery only; camera is always one).
  final bool multiple;

  const MediaRequest({
    this.mode = MediaPickMode.gallery,
    this.kind = MediaKind.image,
    this.multiple = false,
  });
}

/// A vendor-agnostic handle to one acquired media item.
///
/// Carries a [path] (mobile/desktop) and/or [bytes] (web/in-memory) — at least
/// one is present. The bloc tracks this plus its upload state; it does not own
/// where bytes are persisted.
class MediaItem {
  /// Stable id (assigned by the source; unique within a session).
  final String id;

  /// Filesystem path, if available.
  final String? path;

  /// In-memory bytes, if available.
  final Uint8List? bytes;

  /// File name (for display / upload).
  final String name;

  /// MIME type, e.g. `image/jpeg`.
  final String mimeType;

  /// Size in bytes (0 if unknown).
  final int sizeBytes;

  final MediaKind kind;

  const MediaItem({
    required this.id,
    this.path,
    this.bytes,
    required this.name,
    this.mimeType = 'application/octet-stream',
    this.sizeBytes = 0,
    this.kind = MediaKind.image,
  });

  @override
  String toString() => 'MediaItem($id, $name, $kind, ${sizeBytes}B)';
}
