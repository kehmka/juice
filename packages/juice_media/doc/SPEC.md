# juice_media Specification

> **Status:** Implemented (shipping).
> **Package:** `juice_media`
> **Primary Bloc:** `MediaBloc`

## Overview

A **capability-tier** bloc owning media acquisition (camera/gallery) and
**per-item upload state**, behind a `MediaSource` seam and a `MediaUploader`
seam. Exposes `setPermissionStatus` (shared-permissions pattern).

## Domain boundary

- **Owns:** acquired `MediaItem`s and their `UploadState` (progress/url/error).
- **Does NOT own:** byte persistence (storage / backend), the upload transport
  (the uploader seam), or editing/cropping/render UI.

## Seams

- **`MediaSource`** — `pick(MediaRequest) → List<MediaItem>`. Default
  `ImagePickerMediaSource` (`image_picker`; camera + gallery; image + video).
- **`MediaUploader`** — `upload(MediaItem) → MediaUpload`. **Injected** (no
  universal default). `MediaUpload` is handle-based: `progress` stream (0..1),
  `result` future (remote URL), `cancel()`. Mirrors Dio `onSendProgress` +
  `CancelToken`.

`MediaItem` is vendor-agnostic: id, `path` and/or `bytes`, name, mime, size,
kind, and `uri` (set for remote-origin items).

## Remote items (0.2)

Items that arrive **already hosted** (existing backend images) are first-class,
for mixed local/remote galleries. `MediaItem.remote(...)` sets `uri`
(`isRemote == true`). Seed via `MediaConfig.initialItems` or `addRemoteItems(...)`
at runtime. Each is seeded as a `completed` upload (`UploadState.remote`) so it
renders, counts in `allUploaded`, and is skipped by `uploadAll` — uniformly with
locally-uploaded items, no special-casing in the UI. `item.uri` ("came from the
network") is distinct from a local item's `uploads[id].remoteUrl` ("uploaded this
session").

## Selective refresh

| Group | Emitted when |
|---|---|
| `MediaGroups.item(id)` → `media:item:<id>` | that item or its upload changed |
| `MediaGroups.any` → `media:any` | item set changed (add/remove/clear) |
| `MediaGroups.picking` → `media:picking` | acquisition in flight |
| `MediaGroups.permission` → `media:permission` | permission flag changed |
| `MediaGroups.error` → `media:error` | acquisition / upload error |

A progress widget bound to `item(id)` rebuilds only on that item — one item's
progress never rebuilds the gallery.

## Upload concurrency

The bloc owns the upload handles (`_active`) and progress subscriptions
(`_progressSubs`) — lifecycle resources, cancelled in `close()`. `beginUpload`
wires a handle's progress/result to internal events.

**Staleness guard:** callbacks check `_active` membership before emitting. A
**cancel** cleans up *before* the handle's result errors, so a cancelled
upload's error never overwrites the `cancelled` status. A real completion/
failure fires *before* its use case cleans up, so it passes. `close()` snapshots
the maps before awaiting cancellation to avoid concurrent modification.

## State

```dart
class UploadState { final String itemId; final UploadStatus status; // queued/uploading/completed/failed/cancelled
  final double progress; final String? remoteUrl; final String? error; }

class MediaState extends BlocState {
  final List<MediaItem> items;
  final Map<String, UploadState> uploads;
  final bool picking;
  final bool permissionGranted;
  final String? lastError;
  bool get isUploading; bool get allUploaded;
}
```

## Events

`InitializeMediaEvent`, `AcquireMediaEvent(request)`, `RemoveItemEvent`,
`ClearItemsEvent`, `UploadItemEvent`, `UploadAllEvent`, `UploadProgressEvent`*,
`UploadCompletedEvent`*, `UploadFailedEvent`*, `CancelUploadEvent`,
`SetPermissionStatusEvent`. (*internal)

## Fail-loud

`upload` with no uploader → item marked `failed`, `lastError` set, `emitFailure`.
Never a silent no-op.

## Testing

Headless with a fake source + controllable fake uploader: pick/append, pick
error, remove, **per-item selective refresh** (progress on A doesn't touch B),
progress→complete, cancel (→ cancelled, not failed), failure, no-uploader
fail-loud, uploadAll, permission dedup, close disposes both seams. 12 tests.

## Scope

0.1 covers image/video via `image_picker`. Arbitrary file picking (PDF, etc.)
is a separate file-capable `MediaSource`, planned post-0.1.

## Spec Version

| Version | Date | Status |
|---|---|---|
| 1.0 | 2026-05-28 | Implemented |
