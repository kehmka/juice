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
  FakeMediaSource([this.toReturn = const []]);

  @override
  Future<List<MediaItem>> pick(MediaRequest request) async {
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
