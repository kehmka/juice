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

  /// Optional session tag stamped on every item this request acquires (e.g. a
  /// draft id), so concurrent contexts can partition `state.items` — see
  /// `MediaState.inSession`.
  final String? session;

  const MediaRequest({
    this.mode = MediaPickMode.gallery,
    this.kind = MediaKind.image,
    this.multiple = false,
    this.session,
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

  /// Optional session tag (e.g. a draft id) partitioning items that belong to
  /// different contexts in one bloc. Null = untagged.
  final String? session;

  const MediaItem({
    required this.id,
    this.path,
    this.bytes,
    required this.name,
    this.mimeType = 'application/octet-stream',
    this.sizeBytes = 0,
    this.kind = MediaKind.image,
    this.uri,
    this.session,
  });

  /// A remote-origin item — already hosted at [uri], no local bytes.
  const MediaItem.remote({
    required this.id,
    required String uri,
    required this.name,
    this.mimeType = 'image/jpeg',
    this.sizeBytes = 0,
    this.kind = MediaKind.image,
    this.session,
  })  :
        // ignore: prefer_initializing_formals — field is nullable, param is not
        uri = uri,
        path = null,
        bytes = null;

  /// A **local-file** item created from a path (not via `pick()`) — e.g. to
  /// re-upload media whose picker items were lost to an app restart.
  /// Add with `MediaBloc.addLocalItems`, then `upload(id)` works normally.
  const MediaItem.local({
    required this.id,
    required String path,
    required this.name,
    this.mimeType = 'image/jpeg',
    this.sizeBytes = 0,
    this.kind = MediaKind.image,
    this.session,
  })  :
        // ignore: prefer_initializing_formals — field is nullable, param is not
        path = path,
        bytes = null,
        uri = null;

  /// Whether this item arrived already hosted (vs. locally acquired).
  bool get isRemote => uri != null;

  /// Copy with a different [session] tag (other fields are immutable identity).
  MediaItem withSession(String? session) => MediaItem(
        id: id,
        path: path,
        bytes: bytes,
        name: name,
        mimeType: mimeType,
        sizeBytes: sizeBytes,
        kind: kind,
        uri: uri,
        session: session,
      );

  @override
  String toString() =>
      'MediaItem($id, $name, $kind, ${isRemote ? 'remote' : 'local'}'
      '${session == null ? '' : ', session:$session'})';
}
