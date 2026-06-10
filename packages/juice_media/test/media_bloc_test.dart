import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_media/juice_media.dart';

/// Records emitted rebuild groups, to assert per-item selective refresh.
class GroupRecorder {
  final List<Set<String>> emissions = [];
  late final StreamSubscription _sub;
  GroupRecorder(MediaBloc bloc) {
    _sub = bloc.stream.listen((status) {
      final g = status.event?.groupsToRebuild;
      if (g != null) emissions.add(g);
    });
  }
  Set<String> get last => emissions.last;
  Future<void> cancel() => _sub.cancel();
}

/// Returns preset items from `pick`.
class FakeMediaSource implements MediaSource {
  List<MediaItem> toReturn;
  Object? error;
  bool disposed = false;
  int pickCalls = 0;
  FakeMediaSource([this.toReturn = const []]);

  @override
  Future<List<MediaItem>> pick(MediaRequest request) async {
    pickCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (error != null) throw error!;
    return toReturn;
  }

  @override
  Future<void> dispose() async => disposed = true;
}

/// A controllable in-flight upload.
class FakeMediaUpload implements MediaUpload {
  final _progress = StreamController<double>.broadcast();
  final _result = Completer<String>();
  bool cancelled = false;

  void emit(double p) => _progress.add(p);
  void complete(String url) {
    if (!_result.isCompleted) _result.complete(url);
  }

  void fail(Object e) {
    if (!_result.isCompleted) _result.completeError(e);
  }

  @override
  Stream<double> get progress => _progress.stream;
  @override
  Future<String> get result => _result.future;
  @override
  void cancel() {
    cancelled = true;
    if (!_result.isCompleted) _result.completeError(StateError('cancelled'));
  }
}

class FakeMediaUploader implements MediaUploader {
  final Map<String, FakeMediaUpload> uploads = {};
  bool disposed = false;

  @override
  MediaUpload upload(MediaItem item) =>
      uploads[item.id] = FakeMediaUpload();

  @override
  Future<void> dispose() async => disposed = true;
}

MediaItem img(String id) =>
    MediaItem(id: id, name: '$id.jpg', mimeType: 'image/jpeg', sizeBytes: 100);

void main() {
  Future<void> settle([int ms = 20]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  group('MediaState model', () {
    test('defaults', () {
      const s = MediaState();
      expect(s.items, isEmpty);
      expect(s.uploads, isEmpty);
      expect(s.picking, isFalse);
      expect(s.isUploading, isFalse);
    });
  });

  group('Acquisition', () {
    test('pick appends items and toggles picking', () async {
      final src = FakeMediaSource([img('a'), img('b')]);
      final bloc = MediaBloc.withConfig(MediaConfig(source: src));
      await settle();

      bloc.pickFromGallery(multiple: true);
      await settle();

      expect(bloc.state.items.map((i) => i.id), ['a', 'b']);
      expect(bloc.state.picking, isFalse);
      await bloc.close();
    });

    test('pick error surfaces', () async {
      final src = FakeMediaSource()..error = StateError('denied');
      final bloc = MediaBloc.withConfig(MediaConfig(source: src));
      await settle();

      bloc.pickFromGallery();
      await settle();

      expect(bloc.state.lastError, contains('denied'));
      expect(bloc.state.picking, isFalse);
      await bloc.close();
    });

    test('a second pick while one is in flight is ignored', () async {
      final src = FakeMediaSource([img('a')]);
      final bloc = MediaBloc.withConfig(MediaConfig(source: src));
      await settle();

      bloc.pickFromGallery();
      bloc.pickFromGallery(); // guarded — first is still picking
      await settle();

      expect(src.pickCalls, 1);
      await bloc.close();
    });

    test('remove drops the item', () async {
      final src = FakeMediaSource([img('a')]);
      final bloc = MediaBloc.withConfig(MediaConfig(source: src));
      await settle();
      bloc.pickFromGallery();
      await settle();

      bloc.removeItem('a');
      await settle();
      expect(bloc.state.items, isEmpty);
      await bloc.close();
    });
  });

  group('Upload', () {
    test('progress updates, completes with url', () async {
      final src = FakeMediaSource([img('a')]);
      final up = FakeMediaUploader();
      final bloc = MediaBloc.withConfig(MediaConfig(source: src, uploader: up));
      await settle();
      bloc.pickFromGallery();
      await settle();

      bloc.upload('a');
      await settle();
      expect(bloc.state.uploads['a']!.status, UploadStatus.uploading);

      up.uploads['a']!.emit(0.5);
      await settle();
      expect(bloc.state.uploads['a']!.progress, 0.5);

      up.uploads['a']!.complete('https://cdn/a.jpg');
      await settle();
      expect(bloc.state.uploads['a']!.status, UploadStatus.completed);
      expect(bloc.state.uploads['a']!.remoteUrl, 'https://cdn/a.jpg');
      expect(bloc.state.uploads['a']!.progress, 1);

      await bloc.close();
    });

    test('per-item selective refresh: progress on A does not touch B', () async {
      final src = FakeMediaSource([img('a'), img('b')]);
      final up = FakeMediaUploader();
      final bloc = MediaBloc.withConfig(MediaConfig(source: src, uploader: up));
      await settle();
      bloc.pickFromGallery(multiple: true);
      await settle();

      bloc.upload('a');
      bloc.upload('b');
      await settle();

      final rec = GroupRecorder(bloc);
      up.uploads['a']!.emit(0.3);
      await settle();

      expect(rec.last, contains(MediaGroups.item('a')));
      expect(rec.last, isNot(contains(MediaGroups.item('b'))));
      await rec.cancel();
      await bloc.close();
    });

    test('cancel aborts the upload', () async {
      final src = FakeMediaSource([img('a')]);
      final up = FakeMediaUploader();
      final bloc = MediaBloc.withConfig(MediaConfig(source: src, uploader: up));
      await settle();
      bloc.pickFromGallery();
      await settle();

      bloc.upload('a');
      await settle();
      bloc.cancelUpload('a');
      await settle();

      expect(up.uploads['a']!.cancelled, isTrue);
      expect(bloc.state.uploads['a']!.status, UploadStatus.cancelled);
      await bloc.close();
    });

    test('upload failure surfaces and marks failed', () async {
      final src = FakeMediaSource([img('a')]);
      final up = FakeMediaUploader();
      final bloc = MediaBloc.withConfig(MediaConfig(source: src, uploader: up));
      await settle();
      bloc.pickFromGallery();
      await settle();

      bloc.upload('a');
      await settle();
      up.uploads['a']!.fail(StateError('timeout'));
      await settle();

      expect(bloc.state.uploads['a']!.status, UploadStatus.failed);
      expect(bloc.state.uploads['a']!.error, contains('timeout'));
      await bloc.close();
    });

    test('no uploader configured fails loudly', () async {
      final src = FakeMediaSource([img('a')]);
      final bloc = MediaBloc.withConfig(MediaConfig(source: src)); // no uploader
      await settle();
      bloc.pickFromGallery();
      await settle();

      bloc.upload('a');
      await settle();

      expect(bloc.state.uploads['a']!.status, UploadStatus.failed);
      expect(bloc.state.lastError, contains('No uploader'));
      await bloc.close();
    });

    test('uploadAll uploads each pending item', () async {
      final src = FakeMediaSource([img('a'), img('b')]);
      final up = FakeMediaUploader();
      final bloc = MediaBloc.withConfig(MediaConfig(source: src, uploader: up));
      await settle();
      bloc.pickFromGallery(multiple: true);
      await settle();

      bloc.uploadAll();
      await settle();
      expect(bloc.state.uploads['a']!.status, UploadStatus.uploading);
      expect(bloc.state.uploads['b']!.status, UploadStatus.uploading);
      await bloc.close();
    });
  });

  group('Remote items', () {
    test('addRemoteItems seeds completed uploads with the url', () async {
      final bloc = MediaBloc.withConfig(MediaConfig(source: FakeMediaSource()));
      await settle();

      bloc.addRemoteItems([
        const MediaItem.remote(id: 'r1', uri: 'https://cdn/r1.jpg', name: 'r1.jpg'),
      ]);
      await settle();

      final item = bloc.state.items.single;
      expect(item.isRemote, isTrue);
      final up = bloc.state.uploads['r1']!;
      expect(up.status, UploadStatus.completed);
      expect(up.remoteUrl, 'https://cdn/r1.jpg');
      expect(up.progress, 1);
      await bloc.close();
    });

    test('config.initialItems seed remote items at init', () async {
      final bloc = MediaBloc.withConfig(MediaConfig(
        source: FakeMediaSource(),
        initialItems: const [
          MediaItem.remote(id: 'r1', uri: 'https://cdn/r1.jpg', name: 'r1.jpg'),
          MediaItem.remote(id: 'r2', uri: 'https://cdn/r2.jpg', name: 'r2.jpg'),
        ],
      ));
      await settle();

      expect(bloc.state.items.length, 2);
      expect(bloc.state.allUploaded, isTrue);
      await bloc.close();
    });

    test('uploadAll uploads only local items, skipping remote', () async {
      final src = FakeMediaSource([img('local')]);
      final up = FakeMediaUploader();
      final bloc = MediaBloc.withConfig(MediaConfig(
        source: src,
        uploader: up,
        initialItems: const [
          MediaItem.remote(id: 'remote', uri: 'https://cdn/x.jpg', name: 'x.jpg'),
        ],
      ));
      await settle();
      bloc.pickFromGallery();
      await settle();

      bloc.uploadAll();
      await settle();

      // The local item got an upload handle; the remote one did not.
      expect(up.uploads.containsKey('local'), isTrue);
      expect(up.uploads.containsKey('remote'), isFalse);
      expect(bloc.state.uploads['remote']!.status, UploadStatus.completed);
      await bloc.close();
    });

    test('remove drops a remote item', () async {
      final bloc = MediaBloc.withConfig(MediaConfig(
        source: FakeMediaSource(),
        initialItems: const [
          MediaItem.remote(id: 'r1', uri: 'https://cdn/r1.jpg', name: 'r1.jpg'),
        ],
      ));
      await settle();

      bloc.removeItem('r1');
      await settle();
      expect(bloc.state.items, isEmpty);
      expect(bloc.state.uploads.containsKey('r1'), isFalse);
      await bloc.close();
    });
  });

  group('Sessions (draft partitioning)', () {
    test('pick stamps the request session; inSession filters', () async {
      final src = FakeMediaSource([img('a'), img('b')]);
      final bloc = MediaBloc.withConfig(MediaConfig(source: src));
      await settle();

      bloc.pickFromGallery(multiple: true, session: 'draft-1');
      await settle();
      src.toReturn = [img('c')];
      bloc.pickFromGallery(session: 'draft-2');
      await settle();

      expect(bloc.state.inSession('draft-1').map((i) => i.id), ['a', 'b']);
      expect(bloc.state.inSession('draft-2').map((i) => i.id), ['c']);
      await bloc.close();
    });
  });

  group('Local items (post-restart re-upload)', () {
    test('addLocalItems appends uploadable items', () async {
      final src = FakeMediaSource();
      final up = FakeMediaUploader();
      final bloc = MediaBloc.withConfig(MediaConfig(source: src, uploader: up));
      await settle();

      bloc.addLocalItems([
        const MediaItem.local(id: 'l1', path: '/tmp/x.jpg', name: 'x.jpg'),
      ]);
      await settle();
      expect(bloc.state.items.single.id, 'l1');
      expect(bloc.state.items.single.isRemote, isFalse);

      bloc.upload('l1');
      await settle();
      expect(up.uploads.containsKey('l1'), isTrue); // upload path works
      await bloc.close();
    });

    test('addLocalItems rejects a remote-origin item loudly', () async {
      final bloc =
          MediaBloc.withConfig(MediaConfig(source: FakeMediaSource()));
      await settle();

      bloc.addLocalItems([
        const MediaItem.remote(
            id: 'r1', uri: 'https://cdn/x.jpg', name: 'x.jpg'),
      ]);
      await settle();
      // Fails loud (use-case throw routes to the bloc error handler) and the
      // item is NOT added.
      expect(bloc.state.items, isEmpty);
      await bloc.close();
    });
  });

  group('Permission & lifecycle', () {
    test('setPermissionStatus updates (deduped)', () async {
      final bloc = MediaBloc.withConfig(MediaConfig(source: FakeMediaSource()));
      await settle();
      bloc.setPermissionStatus(true);
      await settle();
      expect(bloc.state.permissionGranted, isTrue);
      await bloc.close();
    });

    test('close disposes source and uploader', () async {
      final src = FakeMediaSource();
      final up = FakeMediaUploader();
      final bloc = MediaBloc.withConfig(MediaConfig(source: src, uploader: up));
      await settle();
      await bloc.close();
      expect(src.disposed, isTrue);
      expect(up.disposed, isTrue);
    });
  });
}
