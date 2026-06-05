# juice_media example

A media gallery with per-item upload progress, built with Juice primitives only.

Uses a `DemoMediaSource` (fabricates items, no device) and a `DemoMediaUploader`
(streams progress 0→1 over ~2s, then succeeds) — so the app runs with **no
camera and no backend**. Each tile is a `StatelessJuiceWidget` bound to its own
`MediaGroups.item(id)`, so **only the uploading item's progress bar animates**;
the others stay still.

Demonstrates:
- pick (multiple) → a list of items
- per-item upload with a live progress bar
- per-item cancel, and upload-all
- selective refresh (one item's progress doesn't rebuild the rest)

For a real app, drop `MediaConfig()` (default `ImagePickerMediaSource`) and
inject your own `MediaUploader`.

## Run

```bash
flutter run
```
