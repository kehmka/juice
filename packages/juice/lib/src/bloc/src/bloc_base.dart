part of 'bloc.dart';

/// An object that provides access to a stream of states over time.
abstract class Streamable<State extends Object?> {
  /// The current [stream] of states.
  Stream<State> get stream;
}

/// A [Streamable] that provides synchronous access to the current [currentStatus].
abstract class StateStreamable<State> implements Streamable<State> {
  /// The current [currentStatus].
  State get currentStatus;
}

/// A [StateStreamable] that must be closed when no longer in use.
abstract class StateStreamableSource<State>
    implements StateStreamable<State>, Closable {}

/// An object that must be closed when no longer in use.
abstract class Closable {
  /// Closes the current instance.
  /// The returned future completes when the instance has been closed.
  FutureOr<void> close();

  /// Whether the object is closed.
  ///
  /// An object is considered closed once [close] is called.
  bool get isClosed;
}

/// An object that can emit new states.
abstract class Emittable<State extends Object?> {
  /// Emits a new [state].
  void emit(State state);
}

/// A generic destination for errors.
///
/// Multiple errors can be reported to the sink via `addError`.
abstract class ErrorSink implements Closable {
  /// Adds an [error] to the sink with an optional [stackTrace].
  ///
  /// Must not be called on a closed sink.
  void addError(Object error, [StackTrace? stackTrace]);
}

abstract class BlocBase<State>
    implements StateStreamableSource<State>, Emittable<State>, ErrorSink {
  BlocBase(this._state);

  late final _stateController = StreamController<State>.broadcast();

  State _state;

  @override
  State get currentStatus => _state;

  @override
  Stream<State> get stream => _stateController.stream;

  /// Whether the bloc is closed.
  ///
  /// A bloc is considered closed once [close] is called.
  /// Subsequent state changes cannot occur within a closed bloc.
  @override
  bool get isClosed => _stateController.isClosed;

  @protected
  @visibleForTesting
  @override
  void emit(State state) {
    try {
      if (isClosed) {
        throw StateError('Cannot emit new states after calling close');
      }
      _state = state;
      _stateController.add(_state);
    } catch (error, stackTrace) {
      onError(error, stackTrace);
      rethrow;
    }
  }

  /// Reports an [error] which triggers [onError] with an optional [StackTrace].
  @protected
  @mustCallSuper
  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    onError(error, stackTrace ?? StackTrace.current);
  }

  @protected
  @mustCallSuper
  void onError(Object error, StackTrace stackTrace) {}

  /// Closes the instance.
  /// This method should be called when the instance is no longer needed.
  /// Once [close] is called, the instance can no longer be used.
  @mustCallSuper
  @override
  Future<void> close() async {
    await _stateController.close();
  }
}
