import 'dart:async';

import 'package:juice_realtime/juice_realtime.dart';

/// Demo connector so the app runs with no server — connects after a short
/// delay and echoes whatever you send back as a message.
class DemoRealtimeConnector implements RealtimeConnector {
  @override
  Future<RealtimeConnection> connect() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return _DemoConnection();
  }

  @override
  Future<void> dispose() async {}
}

class _DemoConnection implements RealtimeConnection {
  final _controller = StreamController<RealtimeMessage>();
  var _n = 0;

  @override
  Stream<RealtimeMessage> get messages => _controller.stream;

  @override
  Future<void> send(Object data) async {
    _n++;
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (!_controller.isClosed) {
        _controller.add(RealtimeMessage('echo #$_n: $data'));
      }
    });
  }

  @override
  Future<void> close() async {
    if (!_controller.isClosed) await _controller.close();
  }
}
