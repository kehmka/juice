import 'dart:async';

import 'package:juice_sync/juice_sync.dart';

/// Demo executor (no backend): `ok` succeeds after a beat, `bad` is a permanent
/// failure (dead-letter), `flaky` fails once then succeeds.
class DemoExecutor {
  final Map<String, int> _flakyUsed = {};

  Future<void> call(Mutation m) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (m.type == 'bad') {
      throw const PermanentSyncError('server rejected (422)');
    }
    if (m.type == 'flaky') {
      final used = _flakyUsed[m.id] ?? 0;
      if (used < 1) {
        _flakyUsed[m.id] = used + 1;
        throw StateError('temporary network error');
      }
    }
    // ok / recovered flaky → success
  }
}

/// Holds a manual online/offline toggle for the demo.
class OnlineToggle {
  final _controller = StreamController<bool>.broadcast();
  bool value = true;
  Stream<bool> get stream => _controller.stream;
  void set(bool v) {
    value = v;
    _controller.add(v);
  }

  void dispose() => _controller.close();
}
