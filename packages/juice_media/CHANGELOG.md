# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.1] - 2026-05-28

### Fixed

- `AcquireMediaUseCase` now no-ops if a pick is already in flight (the `picking`
  guard was decorative — a rapid double-tap could launch two pickers).
- A late `UploadProgressEvent` arriving after cancel/complete no longer revives
  the progress bar (guards on `status == uploading`).

## [0.2.0] - 2026-05-28

### Added

- **First-class remote items** — items that arrive already hosted (e.g. existing
  images from your backend), for mixed local/remote galleries.
  - `MediaItem.uri` + `MediaItem.remote(...)` constructor + `isRemote`.
  - `MediaConfig.initialItems` to seed remote items at init.
  - `addRemoteItems(...)` to add them at runtime.
  - Remote items are seeded as a `completed` upload (`UploadState.remote`), so
    they render, count in `allUploaded`, and are skipped by `uploadAll`
    uniformly.

This release is additive and backward-compatible with 0.1.0.

## [0.1.0] - 2026-05-28

### Added

- Initial release.
- **`MediaBloc`** — acquire images/video (camera/gallery) and track **per-item
  upload progress**, with selective rebuilds: a widget bound to
  `MediaGroups.item(id)` rebuilds only when that item (or its upload) changes.
- **`MediaSource`** — acquisition seam; default **`ImagePickerMediaSource`**
  (`image_picker`, camera + gallery, image + video).
- **`MediaUploader` / `MediaUpload`** — upload seam, handle-based
  (progress stream + result future + `cancel()`). Injected; no universal
  default. The bloc owns *progress state*, never the transport.
- **Per-item upload lifecycle** — `queued → uploading → completed / failed /
  cancelled`, with progress, remote URL, cancellation. `upload` / `uploadAll` /
  `cancelUpload`.
- **Fail-loud** — uploading with no uploader configured marks the item failed
  and surfaces `lastError` (never a silent no-op).
- **Permissions** — `setPermissionStatus` entry point (wire camera/photos from
  `juice_permissions` via `PermissionBinding`); no `juice_permissions` dep.
- **Rebuild groups** — `media:item:<id>`, `media:any`, `media:picking`,
  `media:permission`, `media:error`.

### Not yet included

- Arbitrary file picking (PDF, etc.) — a file-capable `MediaSource` is planned
  post-0.1.
