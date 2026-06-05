import 'dart:async';

import 'package:juice_media/juice_media.dart';

/// Demo source so the app runs with no device — each "pick" fabricates an item.
class DemoMediaSource implements MediaSource {
  int _seq = 0;

  @override
  Future<List<MediaItem>> pick(MediaRequest request) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final n = request.multiple ? 3 : 1;
    return [
      for (var i = 0; i < n; i++)
        MediaItem(
          id: 'demo_${_seq++}',
          name: 'photo_$_seq.jpg',
          mimeType: 'image/jpeg',
          sizeBytes: 1024 * (100 + _seq),
          kind: request.kind,
        ),
    ];
  }

  @override
  Future<void> dispose() async {}
}

/// Demo uploader — streams progress 0→1 over ~2s, then "succeeds".
class DemoMediaUploader implements MediaUploader {
  @override
  MediaUpload upload(MediaItem item) => _DemoUpload(item);

  @override
  Future<void> dispose() async {}
}

class _DemoUpload implements MediaUpload {
  final MediaItem item;
  final _progress = StreamController<double>.broadcast();
  final _result = Completer<String>();
  Timer? _timer;
  double _p = 0;

  _DemoUpload(this.item) {
    _timer = Timer.periodic(const Duration(milliseconds: 200), (t) {
      _p += 0.1;
      if (_p >= 1.0) {
        _progress.add(1);
        t.cancel();
        if (!_result.isCompleted) {
          _result.complete('https://cdn.example/${item.name}');
        }
      } else {
        _progress.add(_p);
      }
    });
  }

  @override
  Stream<double> get progress => _progress.stream;
  @override
  Future<String> get result => _result.future;
  @override
  void cancel() {
    _timer?.cancel();
    if (!_result.isCompleted) _result.completeError(StateError('cancelled'));
  }
}
