import 'media_item.dart';

/// Vendor seam for acquiring media from the device.
///
/// `MediaBloc` depends on this, not on a picker plugin — so it's testable with
/// a fake. The default implementation is `ImagePickerMediaSource`.
abstract class MediaSource {
  /// Acquire media per [request]. Returns the picked items, or an empty list
  /// if the user cancelled.
  Future<List<MediaItem>> pick(MediaRequest request);

  /// Release resources.
  Future<void> dispose();
}
