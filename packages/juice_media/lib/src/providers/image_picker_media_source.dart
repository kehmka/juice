import 'package:image_picker/image_picker.dart';

import '../media_item.dart';
import '../media_source.dart';

/// Default [MediaSource] backed by `image_picker` (camera + gallery, images +
/// video). Follow the `image_picker` platform setup (Info.plist /
/// AndroidManifest).
///
/// Arbitrary file picking (PDF, etc.) is out of scope here — that's a separate
/// file-capable `MediaSource` (planned post-0.1).
class ImagePickerMediaSource implements MediaSource {
  final ImagePicker _picker;
  int _seq = 0;

  ImagePickerMediaSource([ImagePicker? picker])
      : _picker = picker ?? ImagePicker();

  @override
  Future<List<MediaItem>> pick(MediaRequest request) async {
    final fromCamera = request.mode == MediaPickMode.camera;

    if (request.kind == MediaKind.video) {
      final file = await _picker.pickVideo(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      );
      return file == null ? [] : [await _toItem(file, MediaKind.video)];
    }

    if (request.multiple && !fromCamera) {
      final files = await _picker.pickMultiImage();
      return [for (final f in files) await _toItem(f, MediaKind.image)];
    }

    final file = await _picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
    );
    return file == null ? [] : [await _toItem(file, MediaKind.image)];
  }

  Future<MediaItem> _toItem(XFile file, MediaKind kind) async {
    final length = await file.length();
    return MediaItem(
      id: 'media_${_seq++}_${file.name}',
      path: file.path,
      name: file.name,
      mimeType: file.mimeType ??
          (kind == MediaKind.video ? 'video/mp4' : 'image/jpeg'),
      sizeBytes: length,
      kind: kind,
    );
  }

  @override
  Future<void> dispose() async {}
}
