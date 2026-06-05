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

  /// Remote URL for a **remote-origin** item (one that arrived already hosted,
  /// e.g. existing images from your backend). Null for locally-acquired items.
  ///
  /// Distinct from a local item's upload result (`uploads[id].remoteUrl`):
  /// `uri` means "came from the network", that means "was uploaded this session".
  final String? uri;

  const MediaItem({
    required this.id,
    this.path,
    this.bytes,
    required this.name,
    this.mimeType = 'application/octet-stream',
    this.sizeBytes = 0,
    this.kind = MediaKind.image,
    this.uri,
  });

  /// A remote-origin item — already hosted at [uri], no local bytes.
  const MediaItem.remote({
    required this.id,
    required String uri,
    required this.name,
    this.mimeType = 'image/jpeg',
    this.sizeBytes = 0,
    this.kind = MediaKind.image,
  })  :
        // ignore: prefer_initializing_formals — field is nullable, param is not
        uri = uri,
        path = null,
        bytes = null;

  /// Whether this item arrived already hosted (vs. locally acquired).
  bool get isRemote => uri != null;

  @override
  String toString() =>
      'MediaItem($id, $name, $kind, ${isRemote ? 'remote' : 'local'})';
}
