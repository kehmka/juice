---
card_schema: "1.0"
package: juice_media
version: 0.3.0
requires:
  juice: ">=1.5.0"
  image_picker: ">=1.1.0"
updated: 2026-06-09
---

# juice_media — AI card

> Media acquisition (camera/gallery) and **per-item upload state** as a Juice
> bloc, behind swappable `MediaSource` + `MediaUploader` seams. Read repo
> `AGENTS.md` for the Juice mental model + gotchas.

## Purpose

**Owns:** acquired `MediaItem`s and their `UploadState` (progress/url/error),
plus the in-flight upload handles.
**Does NOT own:** byte persistence (storage / your backend), the upload
transport (the `MediaUploader` seam), or editing/cropping/render UI.

## When to use

Multi-item pick + per-item upload progress, cancel, retry, permission gating. If
you just need one byte blob, the seam alone is overkill — this earns its keep
when you track a *gallery* of uploads.

## Install

```yaml
dependencies:
  juice_media: ^0.2.1
```

Default source uses `image_picker` — add its platform setup (iOS `Info.plist`
camera + photo-library usage strings; Android manifest entries).

## Construct

`source` defaults to `ImagePickerMediaSource`. `uploader` is **required for
uploads** — there is no universal default; omit it and `upload()` fails loudly.

```dart
final media = MediaBloc.withConfig(MediaConfig(
  uploader: MyUploader(),               // required to upload; null → fail-loud
  source: ImagePickerMediaSource(),     // optional; this is the default
  initialItems: [MediaItem.remote(id: 'a', uri: url, name: 'a.jpg')],
));
```

## Seams

```dart
// Acquisition. Default ImagePickerMediaSource.
abstract class MediaSource {
  Future<List<MediaItem>> pick(MediaRequest request); // [] if user cancelled
  Future<void> dispose();
}

// Upload transport. REQUIRED (no default — every backend differs).
abstract class MediaUploader {
  MediaUpload upload(MediaItem item);  // returns a per-upload handle
  Future<void> dispose();
}

// One in-flight upload. Mirrors Dio onSendProgress + CancelToken.
abstract class MediaUpload {
  Stream<double> get progress;   // 0.0..1.0
  Future<String> get result;     // completes with remote URL; throws on failure
  void cancel();                 // result should error or never complete
}
```

## API

```dart
void pickFromGallery({MediaKind kind = MediaKind.image, bool multiple = false});
void captureFromCamera({MediaKind kind = MediaKind.image});
void addRemoteItems(List<MediaItem> items);   // already-hosted, seeded completed
void removeItem(String id);
void clearItems();
void upload(String id);
void uploadAll();                              // skips completed/uploading
void cancelUpload(String id);
void setPermissionStatus(bool granted);        // wire from juice_permissions
```

## Events

| Event | Effect |
|---|---|
| `InitializeMediaEvent(config)` | apply config; seed `initialItems` as completed |
| `AcquireMediaEvent(request)` | pick/capture; append results (entry-guarded) |
| `AddRemoteItemsEvent(items)` | append already-hosted items |
| `RemoveItemEvent(id)` / `ClearItemsEvent` | drop one / all items + upload state |
| `UploadItemEvent(id)` | start one upload; fail-loud if no uploader |
| `UploadAllEvent` | start every not-completed/uploading item |
| `UploadProgressEvent(id, p)` *internal* | record progress (staleness-guarded) |
| `UploadCompletedEvent(id, url)` *internal* | mark completed |
| `UploadFailedEvent(id, err)` *internal* | mark failed |
| `CancelUploadEvent(id)` | abort handle → status `cancelled` |
| `SetPermissionStatusEvent(bool)` | record camera/photos access (deduped) |

## State

```dart
class MediaState extends BlocState {
  List<MediaItem> items;                 // selection order
  Map<String, UploadState> uploads;      // per item id; absent until upload starts
  bool picking; bool permissionGranted; String? lastError;
  bool get isUploading; bool get allUploaded;   // allUploaded counts remote-origin items (seeded completed)
}
// MediaItem: id, path?/bytes?, name, mimeType, sizeBytes, kind, uri (remote-origin); isRemote
// UploadState: itemId, status, progress(0..1), remoteUrl?, error?; isActive, isDone
// UploadStatus { queued, uploading, completed, failed, cancelled }
```

## Rebuild groups

| Group | Emitted when |
|---|---|
| `MediaGroups.item(id)` → `media:item:<id>` | that item or its upload changed |
| `MediaGroups.any` → `media:any` | item set changed (add/remove/clear) |
| `MediaGroups.picking` → `media:picking` | acquisition in flight |
| `MediaGroups.permission` → `media:permission` | permission flag changed |
| `MediaGroups.error` → `media:error` | acquisition / upload-setup error |

A widget bound to `item(id)` rebuilds only on that item — one upload's progress
never rebuilds the gallery.

## Concurrency

- **`AcquireMediaEvent` is `EventConcurrency.droppable`** (juice ≥ 1.5.0): a pick
  fired while one is in flight is dropped at dispatch (no manual entry guard).
- **Upload staleness guard:** `beginUpload` callbacks check `_active` membership
  before sending; `UploadProgressUseCase` ignores progress unless status is
  still `uploading`. A **cancel** cleans up *before* the handle errors, so a
  cancelled upload's error never overwrites the `cancelled` status; a real
  completion/failure fires *before* its use case cleans up, so it passes.

## Recipes

```dart
// 1. Uploader adapter (Dio onSendProgress + CancelToken)
class DioUploader implements MediaUploader {
  DioUploader(this._dio);
  final Dio _dio;
  @override MediaUpload upload(MediaItem item) => _DioUpload(_dio, item);
  @override Future<void> dispose() async {}
}
class _DioUpload implements MediaUpload {
  _DioUpload(this._dio, this._item) { _start(); }
  final Dio _dio; final MediaItem _item;
  final _progress = StreamController<double>.broadcast();
  final _done = Completer<String>();
  final _cancel = CancelToken();
  void _start() async {
    try {
      final form = FormData.fromMap({'file': MultipartFile.fromBytes(_item.bytes!, filename: _item.name)});
      final r = await _dio.post('/upload', data: form, cancelToken: _cancel,
          onSendProgress: (sent, total) => _progress.add(total > 0 ? sent / total : 0));
      _done.complete(r.data['url'] as String);
    } catch (e) { if (!_done.isCompleted) _done.completeError(e); }
    finally { await _progress.close(); }
  }
  @override Stream<double> get progress => _progress.stream;
  @override Future<String> get result => _done.future;
  @override void cancel() => _cancel.cancel();
}

// 2. Per-item tile (selective rebuild)
class Tile extends StatelessJuiceWidget<MediaBloc> {
  Tile({required this.id}) : super(key: ValueKey(id), groups: {MediaGroups.item(id)});
  final String id;
  @override Widget onBuild(BuildContext c, StreamStatus s) =>
      LinearProgressIndicator(value: bloc.state.uploads[id]?.progress ?? 0);
}
```

## Testing

Headless — fake the source, drive a controllable fake uploader:

```dart
class FakeSource implements MediaSource {
  List<MediaItem> next = [];
  Future<List<MediaItem>> pick(MediaRequest r) async => next;
  Future<void> dispose() async {}
}
class FakeUpload implements MediaUpload {
  final _p = StreamController<double>.broadcast();
  final _r = Completer<String>();
  Stream<double> get progress => _p.stream;
  Future<String> get result => _r.future;
  void cancel() { if (!_r.isCompleted) _r.completeError('cancelled'); }
  void emit(double v) => _p.add(v);
  void finish(String url) => _r.complete(url);
}
final media = MediaBloc.withConfig(MediaConfig(uploader: fakeUploader, source: src));
media.pickFromGallery();
await settle();                          // Future.delayed(20ms)
expect(media.state.items, hasLength(1));
```

## Failure modes

- `upload`/`uploadAll` with **no uploader** → item marked `failed`, `lastError`
  set, `emitFailure` (never a silent no-op).
- `source.pick` throws → `picking: false`, `lastError` set, `error` group.
- Upload result errors → item `failed` with the error string.
- `cancelUpload` → status `cancelled` (distinct from `failed`).

## Anti-patterns

- ❌ Calling `upload()` without configuring a `MediaUploader` and expecting a
  queue — it fails loudly per item.
- ❌ Reaching into `bloc` handle maps (`_active`) — drive via events/API.
- ❌ Treating `item.uri` (remote-origin) as the upload result — the session
  upload URL is `uploads[id].remoteUrl`.
- ❌ Binding a whole-gallery widget to `MediaGroups.item(id)` — use `any`.

## Integrates with

- **juice_permissions** — capability-tier. Wire camera/photos status via a
  `PermissionBinding(permissionsBloc, JuicePermission.camera, onStatus: (s) =>
  mediaBloc.setPermissionStatus(s == PermissionStatus.granted))..start()`. No
  glue package; the binding talks through the callback only.
- **juice_network / Dio / S3 / Firebase Storage** — behind the `MediaUploader`.

## Invariants

- **Remote-origin items** (`MediaItem.remote`, `isRemote == true`) seed as a
  `completed` `UploadState` — they render, count in `allUploaded`, and are
  skipped by `uploadAll`, uniformly with locally-uploaded items.
- `item.uri` ("came from the network") ≠ `uploads[id].remoteUrl` ("uploaded this
  session").
- `close()` snapshots `_active`/`_progressSubs` before awaiting cancellation to
  avoid concurrent modification; disposes both seams.
- 0.2 scope: image/video via `image_picker`. Arbitrary file picking is a
  separate file-capable `MediaSource` — see ROADMAP.

## See also

`SPEC.md` (design depth) · `README.md` (narrative) · repo `AGENTS.md` (framework).
</content>
</invoke>
