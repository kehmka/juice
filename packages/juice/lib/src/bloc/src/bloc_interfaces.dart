import 'dart:async';

/// The interfaces `JuiceBloc` implements.

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
