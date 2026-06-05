# juice_media

Media acquisition (camera/gallery) and **per-item upload state** as a
[Juice](https://pub.dev/packages/juice) bloc, behind swappable seams.

[![pub package](https://img.shields.io/pub/v/juice_media.svg)](https://pub.dev/packages/juice_media)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

## Why

Picking media is one async call; the hard part is the **state around it** —
multiple items, per-item upload progress, cancellation, retry, permissions. This
models all of that as a testable bloc where **each item's progress widget
rebuilds only when that item changes**.

## What it owns

Acquired items and their upload state. It does **not** own byte persistence
(that's storage / your backend), the upload transport (the `MediaUploader`
seam), or editing/cropping UI.

## Install

```yaml
dependencies:
  juice_media: ^0.1.0
```

The default source uses `image_picker` — follow its platform setup (Info.plist /
AndroidManifest camera & photo strings).

## Use

```dart
final media = MediaBloc.withConfig(MediaConfig(
  uploader: MyUploader(),   // required for uploads
));

media.pickFromGallery(multiple: true);
media.captureFromCamera();
media.uploadAll();
```

## Per-item selective rebuild

Each item owns a rebuild group. Progress on one item rebuilds only that tile:

```dart
class Tile extends StatelessJuiceWidget<MediaBloc> {
  Tile({required this.id}) : super(key: ValueKey(id), groups: {MediaGroups.item(id)});
  final String id;

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final up = bloc.state.uploads[id];
    return LinearProgressIndicator(value: up?.progress ?? 0);
  }
}
```

## The upload seam (where your backend plugs in)

There's no universal uploader, so you inject one. It's handle-based — a progress
stream, a result, and a cancel — mirroring real upload clients:

```dart
class MyUploader implements MediaUploader {
  @override
  MediaUpload upload(MediaItem item) => MyUpload(item); // Dio onSendProgress + CancelToken, S3, Firebase Storage…
  @override
  Future<void> dispose() async {}
}

abstract class MediaUpload {
  Stream<double> get progress;   // 0..1
  Future<String> get result;     // remote URL
  void cancel();
}
```

`upload` / `uploadAll` start uploads; `cancelUpload(id)` aborts one. Status flows
`queued → uploading → completed / failed / cancelled`.

## Remote items (mixed galleries)

Real edit screens show **existing hosted images** alongside newly-picked local
ones. Add remote-origin items and they slot into the same gallery — rendered,
counted, and skipped by `uploadAll` automatically (they're seeded as
`completed`):

```dart
// At init…
MediaConfig(
  uploader: MyUploader(),
  initialItems: [
    MediaItem.remote(id: 'a', uri: 'https://cdn/a.jpg', name: 'a.jpg'),
  ],
);

// …or at runtime:
media.addRemoteItems([MediaItem.remote(id: 'b', uri: 'https://cdn/b.jpg', name: 'b.jpg')]);
```

`item.isRemote` distinguishes them. Render remote items with
`Image.network(item.uri!)`, local items from `path`/`bytes`. `uploadAll` uploads
only the local, not-yet-uploaded ones.

## Fail-loud

Calling upload with **no uploader configured** marks the item `failed` and sets
`state.lastError` — never a silent no-op.

## Permissions

Capability-tier: the bloc holds `permissionGranted`, set via
`setPermissionStatus`. Wire it from `juice_permissions`:

```dart
PermissionBinding(permissions, JuicePermission.photos,
  onStatus: (s) => media.setPermissionStatus(s == PermissionStatus.granted),
)..start();
```

No `juice_permissions` dependency leaks in.

## State

| Field / getter | Meaning |
|---|---|
| `items` | acquired `MediaItem`s (selection order) |
| `uploads` | `id → UploadState` (status/progress/remoteUrl/error) |
| `picking` | an acquisition is in flight |
| `isUploading` / `allUploaded` | derived |
| `permissionGranted` / `lastError` | informational |

Rebuild groups: `MediaGroups.item(id)`, `any`, `picking`, `permission`, `error`.

## License

MIT License — see [LICENSE](LICENSE).
