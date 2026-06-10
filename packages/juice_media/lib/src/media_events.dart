import 'package:juice/juice.dart';

import 'media_config.dart';
import 'media_item.dart';

/// Base class for media events.
abstract class MediaEvent extends EventBase {
  @override
  String toString() => runtimeType.toString();
}

/// Apply config.
class InitializeMediaEvent extends MediaEvent {
  final MediaConfig config;
  InitializeMediaEvent({required this.config});
}

/// Acquire media (pick from gallery / capture from camera).
class AcquireMediaEvent extends MediaEvent {
  final MediaRequest request;
  AcquireMediaEvent(this.request);
}

/// Add remote-origin items (already hosted, e.g. from your backend). Each is
/// seeded as a `completed` upload.
class AddRemoteItemsEvent extends MediaEvent {
  final List<MediaItem> items;
  AddRemoteItemsEvent(this.items);
}

/// Add **local-file** items created outside `pick()` (e.g. re-creating items
/// from persisted paths after an app restart, to upload them). Items must be
/// local (a `path`/`bytes`, no `uri`) — a remote-origin item here fails loud.
class AddLocalItemsEvent extends MediaEvent {
  final List<MediaItem> items;
  AddLocalItemsEvent(this.items);
}

/// Remove one acquired item (and any upload state).
class RemoveItemEvent extends MediaEvent {
  final String id;
  RemoveItemEvent(this.id);
}

/// Remove all items.
class ClearItemsEvent extends MediaEvent {}

/// Start uploading one item.
class UploadItemEvent extends MediaEvent {
  final String id;
  UploadItemEvent(this.id);
}

/// Start uploading every item not already completed/uploading.
class UploadAllEvent extends MediaEvent {}

/// Internal: an upload reported progress.
class UploadProgressEvent extends MediaEvent {
  final String id;
  final double progress;
  UploadProgressEvent(this.id, this.progress);
}

/// Internal: an upload completed.
class UploadCompletedEvent extends MediaEvent {
  final String id;
  final String remoteUrl;
  UploadCompletedEvent(this.id, this.remoteUrl);
}

/// Internal: an upload failed.
class UploadFailedEvent extends MediaEvent {
  final String id;
  final Object error;
  UploadFailedEvent(this.id, this.error);
}

/// Cancel an in-flight upload.
class CancelUploadEvent extends MediaEvent {
  final String id;
  CancelUploadEvent(this.id);
}

/// Set whether camera/photos access is allowed (wire from `juice_permissions`).
class SetPermissionStatusEvent extends MediaEvent {
  final bool granted;
  SetPermissionStatusEvent(this.granted);
}
