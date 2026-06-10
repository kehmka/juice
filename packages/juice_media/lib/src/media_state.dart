import 'package:juice/juice.dart';

import 'media_item.dart';
import 'upload_state.dart';

/// Rebuild groups emitted by `MediaBloc`.
///
/// The per-item group is the heart of selective refresh: a progress widget
/// bound to `MediaGroups.item(id)` rebuilds only when *that* item (or its
/// upload) changes — not the whole gallery.
abstract final class MediaGroups {
  /// A specific item or its upload changed. `item('x')` → `media:item:x`.
  static String item(String id) => 'media:item:$id';

  /// The item set changed (added/removed/cleared).
  static const any = 'media:any';

  /// An acquisition is in progress.
  static const picking = 'media:picking';

  /// The (externally-set) permission status changed.
  static const permission = 'media:permission';

  /// An error occurred (acquisition or upload setup).
  static const error = 'media:error';

  static const all = {any, picking, permission, error};
}

/// Immutable media state: acquired items and their upload progress.
class MediaState extends BlocState {
  /// Acquired items, in selection order.
  final List<MediaItem> items;

  /// Upload state per item id (absent until upload starts).
  final Map<String, UploadState> uploads;

  /// An acquisition (pick/capture) is in flight.
  final bool picking;

  /// Whether the app may access camera/photos. Set externally via
  /// `setPermissionStatus`. Informational.
  final bool permissionGranted;

  /// Last acquisition/upload-setup error.
  final String? lastError;

  const MediaState({
    this.items = const [],
    this.uploads = const {},
    this.picking = false,
    this.permissionGranted = false,
    this.lastError,
  });

  static const initial = MediaState();

  /// Items stamped with [session] (see `MediaRequest.session` /
  /// `MediaItem.session`) — lets concurrent contexts (e.g. drafts) partition
  /// one bloc's items.
  List<MediaItem> inSession(String session) =>
      items.where((i) => i.session == session).toList();

  /// Any upload currently in flight.
  bool get isUploading =>
      uploads.values.any((u) => u.status == UploadStatus.uploading);

  /// Every item has a completed upload.
  bool get allUploaded =>
      items.isNotEmpty &&
      items.every((i) => uploads[i.id]?.status == UploadStatus.completed);

  MediaState copyWith({
    List<MediaItem>? items,
    Map<String, UploadState>? uploads,
    bool? picking,
    bool? permissionGranted,
    Object? lastError = _unset,
  }) {
    return MediaState(
      items: items ?? this.items,
      uploads: uploads ?? this.uploads,
      picking: picking ?? this.picking,
      permissionGranted: permissionGranted ?? this.permissionGranted,
      lastError: identical(lastError, _unset) ? this.lastError : lastError as String?,
    );
  }

  @override
  String toString() =>
      'MediaState(${items.length} items, uploading: $isUploading, picking: $picking)';
}

const Object _unset = Object();
