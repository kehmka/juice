import 'media_source.dart';
import 'media_uploader.dart';
import 'providers/image_picker_media_source.dart';

/// Configures a `MediaBloc`.
class MediaConfig {
  /// Where media is acquired. Defaults to `ImagePickerMediaSource`.
  final MediaSource source;

  /// How media is uploaded. **Required for uploads** — there's no universal
  /// default. If null, calling upload fails loudly.
  final MediaUploader? uploader;

  MediaConfig({
    MediaSource? source,
    this.uploader,
  }) : source = source ?? ImagePickerMediaSource();
}
