import 'package:juice/juice.dart';

import 'media_config.dart';
import 'media_events.dart';
import 'media_item.dart';
import 'media_source.dart';
import 'media_state.dart';
import 'media_uploader.dart';
import 'use_cases/acquire_media_use_case.dart';
import 'use_cases/add_remote_items_use_case.dart';
import 'use_cases/cancel_upload_use_case.dart';
import 'use_cases/clear_items_use_case.dart';
import 'use_cases/initialize_media_use_case.dart';
import 'use_cases/remove_item_use_case.dart';
import 'use_cases/set_permission_status_use_case.dart';
import 'use_cases/upload_all_use_case.dart';
import 'use_cases/upload_completed_use_case.dart';
import 'use_cases/upload_failed_use_case.dart';
import 'use_cases/upload_item_use_case.dart';
import 'use_cases/upload_progress_use_case.dart';

/// A media bloc: acquire images/video (camera/gallery) and track **per-item
/// upload progress**, behind swappable [MediaSource] and [MediaUploader] seams.
///
/// Capability-tier: exposes [setPermissionStatus], wired from `juice_permissions`
/// via a `PermissionBinding`. Owns acquisition + upload *state* — not byte
/// persistence (storage) or the upload transport (the uploader seam).
///
/// ```dart
/// final media = MediaBloc.withConfig(MediaConfig(uploader: MyUploader()));
/// media.pickFromGallery();
/// media.uploadAll();
/// ```
class MediaBloc extends JuiceBloc<MediaState> {
  late MediaConfig _config;

  /// Active upload handles, per item id (for cancellation).
  final Map<String, MediaUpload> _active = {};

  /// Progress subscriptions, per item id.
  final Map<String, StreamSubscription<double>> _progressSubs = {};

  MediaBloc()
      : super(
          MediaState.initial,
          [
            () => UseCaseBuilder(
                typeOfEvent: InitializeMediaEvent,
                useCaseGenerator: () => InitializeMediaUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: AcquireMediaEvent,
                useCaseGenerator: () => AcquireMediaUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: AddRemoteItemsEvent,
                useCaseGenerator: () => AddRemoteItemsUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: RemoveItemEvent,
                useCaseGenerator: () => RemoveItemUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: ClearItemsEvent,
                useCaseGenerator: () => ClearItemsUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: UploadItemEvent,
                useCaseGenerator: () => UploadItemUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: UploadAllEvent,
                useCaseGenerator: () => UploadAllUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: UploadProgressEvent,
                useCaseGenerator: () => UploadProgressUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: UploadCompletedEvent,
                useCaseGenerator: () => UploadCompletedUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: UploadFailedEvent,
                useCaseGenerator: () => UploadFailedUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: CancelUploadEvent,
                useCaseGenerator: () => CancelUploadUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: SetPermissionStatusEvent,
                useCaseGenerator: () => SetPermissionStatusUseCase()),
          ],
        );

  /// Create and initialize in one step.
  factory MediaBloc.withConfig(MediaConfig config) {
    final bloc = MediaBloc();
    bloc.send(InitializeMediaEvent(config: config));
    return bloc;
  }

  // === Config (used by use cases) ===

  void configure(MediaConfig config) => _config = config;
  MediaSource get source => _config.source;
  MediaUploader? get uploader => _config.uploader;

  // === Upload orchestration (lifecycle lives here) ===

  /// Begin an upload: wire its progress stream and result to internal events.
  /// Caller must ensure [uploader] is non-null.
  void beginUpload(MediaItem item) {
    final handle = _config.uploader!.upload(item);
    _active[item.id] = handle;
    // The `_active` membership guard drops stale callbacks: a cancel cleans up
    // *before* the handle's result errors, so a cancelled upload's error never
    // overwrites the cancelled status (cleanup-before-callback). A real
    // completion/failure fires before its use case cleans up, so it passes.
    _progressSubs[item.id] = handle.progress.listen(
      (p) {
        if (!isClosed && _active.containsKey(item.id)) {
          send(UploadProgressEvent(item.id, p));
        }
      },
      onError: (Object e) {
        if (!isClosed && _active.containsKey(item.id)) {
          send(UploadFailedEvent(item.id, e));
        }
      },
    );
    handle.result.then((url) {
      if (!isClosed && _active.containsKey(item.id)) {
        send(UploadCompletedEvent(item.id, url));
      }
    }).catchError((Object e) {
      if (!isClosed && _active.containsKey(item.id)) {
        send(UploadFailedEvent(item.id, e));
      }
    });
  }

  /// Cancel an active upload's handle and release its resources.
  void cancelActiveUpload(String id) {
    _active[id]?.cancel();
    cleanupUpload(id);
  }

  /// Release the handle/subscription for a finished or cancelled upload.
  void cleanupUpload(String id) {
    _progressSubs.remove(id)?.cancel();
    _active.remove(id);
  }

  bool isUploadActive(String id) => _active.containsKey(id);

  // === Convenience API ===

  void pickFromGallery({MediaKind kind = MediaKind.image, bool multiple = false}) =>
      send(AcquireMediaEvent(
          MediaRequest(mode: MediaPickMode.gallery, kind: kind, multiple: multiple)));

  void captureFromCamera({MediaKind kind = MediaKind.image}) => send(
      AcquireMediaEvent(MediaRequest(mode: MediaPickMode.camera, kind: kind)));

  /// Add remote-origin items (already hosted) to the gallery.
  void addRemoteItems(List<MediaItem> items) =>
      send(AddRemoteItemsEvent(items));

  void removeItem(String id) => send(RemoveItemEvent(id));
  void clearItems() => send(ClearItemsEvent());
  void upload(String id) => send(UploadItemEvent(id));
  void uploadAll() => send(UploadAllEvent());
  void cancelUpload(String id) => send(CancelUploadEvent(id));
  void setPermissionStatus(bool granted) =>
      send(SetPermissionStatusEvent(granted));

  @override
  Future<void> close() async {
    // Snapshot then clear before awaiting — cancelling a handle can schedule
    // callbacks that would otherwise mutate these maps mid-iteration.
    final handles = _active.values.toList();
    final subs = _progressSubs.values.toList();
    _active.clear();
    _progressSubs.clear();
    for (final h in handles) {
      h.cancel();
    }
    for (final s in subs) {
      await s.cancel();
    }
    try {
      await _config.source.dispose();
      await _config.uploader?.dispose();
    } catch (_) {
      // Config may never have been applied; ignore.
    }
    await super.close();
  }
}
