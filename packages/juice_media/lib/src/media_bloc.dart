import 'package:juice/juice.dart';

import 'media_config.dart';
import 'media_events.dart';
import 'media_item.dart';
import 'media_source.dart';
import 'media_state.dart';
import 'media_uploader.dart';
import 'use_cases/acquire_media_use_case.dart';
import 'use_cases/add_local_items_use_case.dart';
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
  MediaConfig? _config;

  /// Active upload handles, per item id (for cancellation).
  final Map<String, MediaUpload> _active = {};

  MediaBloc()
      : super(
          MediaState.initial,
          [
            () => UseCaseBuilder(
                  typeOfEvent: InitializeMediaEvent,
                  useCaseGenerator: () => InitializeMediaUseCase(),
                  concurrency: EventConcurrency.droppable,
                ),
            // droppable: a pick fired while one is in flight is ignored
            // (juice ≥ 1.5.0) — replaces a manual `state.picking` entry guard.
            () => UseCaseBuilder(
                typeOfEvent: AcquireMediaEvent,
                useCaseGenerator: () => AcquireMediaUseCase(),
                concurrency: EventConcurrency.droppable),
            () => UseCaseBuilder(
                  typeOfEvent: AddRemoteItemsEvent,
                  useCaseGenerator: () => AddRemoteItemsUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: AddLocalItemsEvent,
                  useCaseGenerator: () => AddLocalItemsUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: RemoveItemEvent,
                  useCaseGenerator: () => RemoveItemUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: ClearItemsEvent,
                  useCaseGenerator: () => ClearItemsUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: UploadItemEvent,
                  useCaseGenerator: () => UploadItemUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: UploadAllEvent,
                  useCaseGenerator: () => UploadAllUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: UploadProgressEvent,
                  useCaseGenerator: () => UploadProgressUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: UploadCompletedEvent,
                  useCaseGenerator: () => UploadCompletedUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: UploadFailedEvent,
                  useCaseGenerator: () => UploadFailedUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: CancelUploadEvent,
                  useCaseGenerator: () => CancelUploadUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: SetPermissionStatusEvent,
                  useCaseGenerator: () => SetPermissionStatusUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
          ],
        );

  /// Create and initialize in one step.
  factory MediaBloc.withConfig(MediaConfig config) {
    final bloc = MediaBloc();
    bloc.send(InitializeMediaEvent(config: config));
    return bloc;
  }

  // === Config (used by use cases) ===

  /// Store the config during initialization. One per bloc: a second
  /// `InitializeMediaEvent` after the first completed is refused here (the
  /// first provider stays owned and live), loudly, through the use case's
  /// error path.
  void configure(MediaConfig config) {
    if (_config != null) {
      throw StateError(
          'MediaBloc is already initialized; it owns one config for its life');
    }
    _config = config;
  }

  MediaSource get source => config.source;
  MediaUploader? get uploader => config.uploader;

  /// The config [InitializeMediaEvent] applied. Throws before that.
  MediaConfig get config =>
      _config ??
      (throw StateError(
          'MediaBloc is not initialized: send InitializeMediaEvent '
          '(or use MediaBloc.withConfig) first'));

  // === Upload orchestration (lifecycle lives here) ===

  /// Begin an upload: wire its progress stream and result to internal events.
  /// Caller must ensure [uploader] is non-null. The progress stream is a
  /// bloc-owned binding keyed by item: cancelled before the use cases close,
  /// unbound by [cleanupUpload], ended by a stream error (which fails the
  /// upload).
  void beginUpload(MediaItem item) {
    if (_active.containsKey(item.id)) {
      throw StateError('MediaBloc: an upload is already active for ${item.id}');
    }
    final handle = uploader!.upload(item);
    _active[item.id] = handle;
    // The identity guard drops stale callbacks: a cancel cleans up *before*
    // the handle's result errors, so a cancelled upload's error never
    // overwrites the cancelled status — and never fails a NEW upload of the
    // same item that started meanwhile (the guard is the handle, not the id).
    // A real completion/failure fires before its use case cleans up, so it
    // passes.
    bool live() => identical(_active[item.id], handle);
    bindStream<double>(
      handle.progress,
      (p) {
        if (live()) send(UploadProgressEvent(item.id, p));
      },
      key: _progressKey(item.id),
      onError: (e, _) {
        if (live()) send(UploadFailedEvent(item.id, e));
      },
    );
    handle.result.then((url) {
      if (!isClosing && live()) send(UploadCompletedEvent(item.id, url));
    }).catchError((Object e) {
      if (!isClosing && live()) send(UploadFailedEvent(item.id, e));
    });
  }

  /// Cancel an active upload's handle and release its resources.
  void cancelActiveUpload(String id) {
    _active[id]?.cancel();
    cleanupUpload(id);
  }

  /// Release the handle/binding for a finished or cancelled upload.
  void cleanupUpload(String id) {
    unbind(_progressKey(id));
    _active.remove(id);
  }

  static String _progressKey(String id) => 'upload:$id';

  bool isUploadActive(String id) => _active.containsKey(id);

  // === Convenience API ===

  void pickFromGallery(
          {MediaKind kind = MediaKind.image,
          bool multiple = false,
          String? session}) =>
      send(AcquireMediaEvent(MediaRequest(
          mode: MediaPickMode.gallery,
          kind: kind,
          multiple: multiple,
          session: session)));

  void captureFromCamera({MediaKind kind = MediaKind.image, String? session}) =>
      send(AcquireMediaEvent(MediaRequest(
          mode: MediaPickMode.camera, kind: kind, session: session)));

  /// Add local-file items created outside `pick()` (e.g. rebuilt from
  /// persisted paths after a restart, to upload them).
  void addLocalItems(List<MediaItem> items) => send(AddLocalItemsEvent(items));

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

  // Memoized like the core's close(): a second caller awaits the first
  // teardown, so the provider is disposed once. `super.close()` is invoked
  // here (the core requires it) and awaited inside.
  @override
  Future<void> close() => _closeOnce ??= _close(super.close());
  Future<void>? _closeOnce;

  Future<void> _close(Future<void> closing) async {
    // The bloc closes first: every progress binding is cancelled before the
    // handles are cancelled and the source and uploader are disposed. An
    // uninitialized bloc has neither.
    await closing;
    // Snapshot then clear before cancelling — cancelling a handle can schedule
    // callbacks that would otherwise mutate the map mid-iteration.
    final handles = _active.values.toList();
    _active.clear();
    for (final h in handles) {
      try {
        h.cancel();
      } catch (error, stackTrace) {
        _logCloseFailure('MediaUpload cancel failed', error, stackTrace);
      }
    }
    final config = _config;
    if (config == null) return;
    // Each seam is disposed whatever the other does; each failure is logged.
    try {
      await config.source.dispose();
    } catch (error, stackTrace) {
      _logCloseFailure('MediaSource dispose failed', error, stackTrace);
    }
    try {
      await config.uploader?.dispose();
    } catch (error, stackTrace) {
      _logCloseFailure('MediaUploader dispose failed', error, stackTrace);
    }
  }

  void _logCloseFailure(String what, Object error, StackTrace stackTrace) =>
      JuiceLoggerConfig.logger.logError(what, error, stackTrace,
          context: {'type': 'bloc_error', 'bloc': 'MediaBloc'});
}
