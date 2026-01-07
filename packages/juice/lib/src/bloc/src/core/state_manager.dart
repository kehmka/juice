import 'dart:async';

/// Manages state storage and stream emission for a bloc.
///
/// This is a pure state container with no knowledge of events or use cases.
/// It provides:
/// - Current state access
/// - State change stream for listeners
/// - Closed state tracking
///
/// Example:
/// ```dart
/// final manager = StateManager<int>(0);
/// manager.stream.listen((state) => print('State: $state'));
/// manager.emit(1); // Prints: State: 1
/// await manager.close();
/// ```
class StateManager<State> {
  /// Creates a StateManager with an initial state.
  StateManager(State initialState) : _state = initialState;

  final _controller = StreamController<State>.broadcast();
  State _state;
  bool _isClosed = false;

  /// The current state.
  State get current => _state;

  /// Stream of state changes.
  ///
  /// This is a broadcast stream, allowing multiple listeners.
  Stream<State> get stream => _controller.stream;

  /// Whether the manager has been closed.
  bool get isClosed => _isClosed;

  /// Emits a new state to all listeners.
  ///
  /// The state is stored and broadcast to all stream listeners.
  ///
  /// Throws [StateError] if called after [close].
  void emit(State state) {
    if (_isClosed) {
      throw StateError('Cannot emit state after StateManager is closed');
    }
    _state = state;
    _controller.add(state);
  }

  /// Closes the state manager and its stream.
  ///
  /// After calling close:
  /// - No more states can be emitted
  /// - The stream will complete
  /// - [isClosed] will return true
  ///
  /// This method is idempotent - calling it multiple times has no effect.
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    await _controller.close();
  }
}
