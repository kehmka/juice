import 'dart:io';
import 'package:juice/juice.dart';

class WebSocketService {
  WebSocket? _socket;
  StreamController<String>? _controller;
  StreamSubscription? _subscription;
  bool _isDisposed = false;

  Stream<String> get messages => _controller?.stream ?? const Stream.empty();

  Future<void> connect(String url) async {
    if (_isDisposed) {
      throw StateError('WebSocketService has been disposed');
    }

    // Clean up any existing connection
    await disconnect();

    // Create new controller
    _controller = StreamController<String>.broadcast(
      onCancel: () {
        // When last listener disconnects, close everything
        if (!(_controller?.hasListener ?? false)) {
          disconnect();
        }
      },
    );

    try {
      _socket = await WebSocket.connect(url);
      JuiceLoggerConfig.logger.log('Connected to WebSocket (io): $url');

      _subscription = _socket!.listen(
        (data) {
          if (!_isDisposed && !(_controller?.isClosed ?? true)) {
            _controller?.add(data.toString());
          }
        },
        onError: (error) {
          if (!_isDisposed && !(_controller?.isClosed ?? true)) {
            JuiceLoggerConfig.logger.log('WebSocket error (io): $error');
            _controller?.addError('WebSocket error (io): $error');
          }
        },
        onDone: () {
          if (!_isDisposed && !(_controller?.isClosed ?? true)) {
            JuiceLoggerConfig.logger.log('WebSocket closed (io)');
            disconnect();
          }
        },
      );
    } catch (e) {
      JuiceLoggerConfig.logger.log('Failed to connect to WebSocket (io): $e');
      if (!_isDisposed && !(_controller?.isClosed ?? true)) {
        _controller?.addError(e);
      }
      rethrow;
    }
  }

  void sendMessage(String message) {
    if (_isDisposed) {
      throw StateError('WebSocketService has been disposed');
    }

    if (_socket != null && _socket!.readyState == WebSocket.open) {
      _socket!.add(message);
    } else {
      throw StateError('WebSocket is not connected');
    }
  }

  Future<void> disconnect() async {
    // Cancel socket subscription first
    await _subscription?.cancel();
    _subscription = null;

    // Close WebSocket next
    if (_socket != null) {
      await _socket!.close();
      _socket = null;
    }

    // Finally close the controller
    if (_controller != null && !_controller!.isClosed) {
      await _controller!.close();
      _controller = null;
    }
  }

  Future<void> dispose() async {
    _isDisposed = true;
    await disconnect();
  }
}
