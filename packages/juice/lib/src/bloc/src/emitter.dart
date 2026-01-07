part of 'bloc.dart';

/// Interface for emitting states in response to events.
///
/// The Emitter provides methods for handling state emissions and working with
/// streams in event handlers. It ensures proper cleanup and cancellation of
/// ongoing operations.
abstract class Emitter<State> {
  /// Processes elements from a stream without transforming the bloc state.
  ///
  /// Use this method when you need to perform side effects in response to
  /// stream events without directly emitting new states.
  ///
  /// Parameters:
  /// * [stream] - The source stream to process
  /// * [onData] - Callback for handling each stream event
  /// * [onError] - Optional error handler
  Future<void> onEach<T>(
    Stream<T> stream, {
    required void Function(T data) onData,
    void Function(Object error, StackTrace stackTrace)? onError,
  });

  /// Processes elements from a stream and transforms them into new states.
  ///
  /// Use this method when you need to emit new states in response to
  /// stream events.
  ///
  /// Parameters:
  /// * [stream] - The source stream to process
  /// * [onData] - Transforms stream events into new states
  /// * [onError] - Optional error handler that can provide error states
  Future<void> forEach<T>(
    Stream<T> stream, {
    required State Function(T data) onData,
    State Function(Object error, StackTrace stackTrace)? onError,
  });

  /// Whether the associated event handler has completed or been cancelled.
  bool get isDone;

  /// Emits a new state.
  ///
  /// This is the primary method for updating bloc state in response to events.
  void call(State state);
}

/// Internal implementation of the Emitter interface.
///
/// Handles the details of state emission, stream subscription management,
/// and cleanup of resources.
class _Emitter<State> implements Emitter<State> {
  _Emitter(this._emit);

  final void Function(State state) _emit;
  final _completer = Completer<void>();
  final _disposables = <FutureOr<void> Function()>[];

  var _isCancelled = false;
  var _isCompleted = false;

  @override
  Future<void> onEach<T>(
    Stream<T> stream, {
    required void Function(T data) onData,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    final completer = Completer<void>();
    StreamSubscription<T>? subscription;

    try {
      subscription = stream.listen(
        onData,
        onDone: completer.complete,
        onError: onError ?? completer.completeError,
        cancelOnError: onError == null,
      );
      _disposables.add(subscription.cancel);
    } catch (e, _) {
      await subscription?.cancel();
      rethrow;
    }

    return Future.any([future, completer.future]).whenComplete(() async {
      await subscription?.cancel();
      _disposables.remove(subscription?.cancel);
    });
  }

  @override
  Future<void> forEach<T>(
    Stream<T> stream, {
    required State Function(T data) onData,
    State Function(Object error, StackTrace stackTrace)? onError,
  }) {
    return onEach<T>(
      stream,
      onData: (data) {
        try {
          call(onData(data));
        } catch (e, stack) {
          if (onError != null) {
            call(onError(e, stack));
          } else {
            rethrow;
          }
        }
      },
      onError: onError != null
          ? (Object error, StackTrace stackTrace) {
              call(onError(error, stackTrace));
            }
          : null,
    );
  }

  @override
  void call(State state) {
    if (!_isCancelled) _emit(state);
  }

  @override
  bool get isDone => _isCancelled || _isCompleted;

  /// Cancels this emitter and cleans up resources.
  ///
  /// Called when the associated event handler needs to be cancelled.
  Future<void> cancel() async {
    if (isDone) return;
    _isCancelled = true;
    await _close();
  }

  /// Marks this emitter as completed and cleans up resources.
  ///
  /// Called when the associated event handler completes normally.
  Future<void> complete() async {
    if (isDone) return;
    _isCompleted = true;
    await _close();
  }

  /// Internal cleanup method that disposes resources and completes the emitter.
  Future<void> _close() async {
    try {
      final futures = _disposables.map((d) => Future(() => d.call()));
      await Future.wait(futures, eagerError: false).catchError((error, stack) {
        JuiceLoggerConfig.logger
            .logError("Error during emitter cleanup", error, stack);
        return <void>[];
      });
    } finally {
      _disposables.clear();
      if (!_completer.isCompleted) _completer.complete();
    }
  }

  Future<void> get future => _completer.future;
}
