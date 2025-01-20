import 'package:juice/juice.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html';

class WebSocketService {
  WebSocket? _socket;
  StreamController<String>? _controller;
  final List<StreamSubscription> _subscriptions = [];
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
      _socket = WebSocket(url);

      // Listen to open event
      _subscriptions.add(
        _socket!.onOpen.listen((_) {
          if (!_isDisposed && !(_controller?.isClosed ?? true)) {
            JuiceLoggerConfig.logger.log('Connected to WebSocket (web): $url');
          }
        }),
      );

      // Listen to messages
      _subscriptions.add(
        _socket!.onMessage.listen((event) {
          if (!_isDisposed && !(_controller?.isClosed ?? true)) {
            _controller?.add(event.data.toString());
          }
        }),
      );

      // Listen to errors
      _subscriptions.add(
        _socket!.onError.listen((_) {
          if (!_isDisposed && !(_controller?.isClosed ?? true)) {
            JuiceLoggerConfig.logger.log('WebSocket error (web)');
            _controller?.addError('WebSocket error (web)');
          }
        }),
      );

      // Listen to close events
      _subscriptions.add(
        _socket!.onClose.listen((_) {
          if (!_isDisposed && !(_controller?.isClosed ?? true)) {
            JuiceLoggerConfig.logger.log('WebSocket closed (web)');
            disconnect();
          }
        }),
      );

      // Wait for connection or error
      await _waitForConnection();
    } catch (e) {
      JuiceLoggerConfig.logger.log('Failed to connect to WebSocket (web): $e');
      if (!_isDisposed && !(_controller?.isClosed ?? true)) {
        _controller?.addError(e);
      }
      rethrow;
    }
  }

  Future<void> _waitForConnection() {
    if (_socket == null) return Future.error('Socket is null');

    final completer = Completer<void>();

    // Complete on open
    final openSub = _socket!.onOpen.listen((_) {
      if (!completer.isCompleted) completer.complete();
    });

    // Complete with error on error
    final errorSub = _socket!.onError.listen((_) {
      if (!completer.isCompleted) {
        completer.completeError('Failed to establish WebSocket connection');
      }
    });

    // Add to cleanup list
    _subscriptions.addAll([openSub, errorSub]);

    // Add timeout
    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        if (!completer.isCompleted) {
          completer.completeError('WebSocket connection timeout');
        }
        return completer.future;
      },
    );
  }

  void sendMessage(String message) {
    if (_isDisposed) {
      throw StateError('WebSocketService has been disposed');
    }

    if (_socket != null && _socket!.readyState == WebSocket.OPEN) {
      _socket!.send(message);
    } else {
      throw StateError('WebSocket is not connected');
    }
  }

  Future<void> disconnect() async {
    // Cancel all subscriptions first
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();

    // Close WebSocket next
    _socket?.close();
    _socket = null;

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
