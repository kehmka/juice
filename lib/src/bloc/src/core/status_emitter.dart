import '../bloc_state.dart';
import '../bloc_event.dart';
import '../stream_status.dart';
import '../juice_logger.dart';
import '../../../ui/src/widget_support.dart';
import 'state_manager.dart';

/// Handles emission of StreamStatus with proper logging and group management.
///
/// StatusEmitter wraps a StateManager and provides typed methods for emitting
/// different status types (update, waiting, failure, cancel). It also handles:
/// - Logging of all emissions
/// - Rebuild group management on events
/// - Validation of group constraints
///
/// Example:
/// ```dart
/// final emitter = StatusEmitter(
///   stateManager: stateManager,
///   logger: logger,
///   blocName: 'CounterBloc',
/// );
///
/// emitter.emitUpdate(event, newState, {'counter'});
/// ```
class StatusEmitter<TState extends BlocState> {
  /// Creates a StatusEmitter.
  ///
  /// [stateManager] is the underlying state manager to emit to.
  /// [logger] is used for logging all emissions.
  /// [blocName] is included in log context for identification.
  StatusEmitter({
    required StateManager<StreamStatus<TState>> stateManager,
    required JuiceLogger logger,
    required String blocName,
  })  : _stateManager = stateManager,
        _logger = logger,
        _blocName = blocName;

  final StateManager<StreamStatus<TState>> _stateManager;
  final JuiceLogger _logger;
  final String _blocName;

  /// The current state from the status.
  TState get state => _stateManager.current.state;

  /// The previous state from the status.
  TState get oldState => _stateManager.current.oldState;

  /// The current full status.
  StreamStatus<TState> get currentStatus => _stateManager.current;

  /// Whether the underlying state manager is closed.
  bool get isClosed => _stateManager.isClosed;

  /// Emits an updating status.
  ///
  /// Used for normal state transitions after successful operations.
  ///
  /// [event] - The event that triggered this update.
  /// [newState] - The new state to emit. If null, uses current state.
  /// [groups] - The rebuild groups to notify.
  /// [skipIfSame] - If true, skips emission when newState equals current state.
  ///   This helps prevent unnecessary widget rebuilds when state hasn't changed.
  void emitUpdate(
    EventBase event,
    TState? newState,
    Set<String>? groups, {
    bool skipIfSame = false,
  }) {
    if (skipIfSame && newState == state) {
      _logger.log('Skipping duplicate state emission', context: {
        'type': 'state_emission_skipped',
        'bloc': _blocName,
        'event': event.runtimeType.toString(),
      });
      return;
    }
    _emit(StreamStatus.updating, 'update', event, newState, groups);
  }

  /// Emits a waiting status.
  ///
  /// Used to indicate an async operation is in progress.
  void emitWaiting(EventBase event, TState? newState, Set<String>? groups) {
    _emit(StreamStatus.waiting, 'waiting', event, newState, groups);
  }

  /// Emits a failure status.
  ///
  /// Used to indicate an operation has failed.
  ///
  /// [error] - The error that caused the failure.
  /// [errorStackTrace] - The stack trace where the error occurred.
  void emitFailure(
    EventBase event,
    TState? newState,
    Set<String>? groups, {
    Object? error,
    StackTrace? errorStackTrace,
  }) {
    _emitFailure(event, newState, groups, error, errorStackTrace);
  }

  /// Emits a canceling status.
  ///
  /// Used to indicate an operation was cancelled.
  void emitCancel(EventBase event, TState? newState, Set<String>? groups) {
    _emit(StreamStatus.canceling, 'cancel', event, newState, groups);
  }

  void _emit(
    StreamStatus<TState> Function(TState, TState, EventBase?) factory,
    String statusName,
    EventBase event,
    TState? newState,
    Set<String>? groupsToRebuild,
  ) {
    if (_stateManager.isClosed) {
      throw StateError('Cannot emit $statusName after bloc is closed');
    }

    _logger.log('Emitting $statusName', context: {
      'type': 'state_emission',
      'status': statusName,
      'state': '${newState ?? state}',
      'bloc': _blocName,
      'groups': groupsToRebuild?.toString(),
      'event': event.runtimeType.toString(),
    });

    // Apply default groups if not specified
    final groups = groupsToRebuild ?? rebuildAlways;

    // Validate group constraints
    assert(
      !groups.contains('*') || groups.length == 1,
      "Cannot mix '*' with other groups",
    );

    // Merge groups onto the event
    event.groupsToRebuild = {...?event.groupsToRebuild, ...groups};

    // Emit the status
    _stateManager.emit(factory(newState ?? state, state, event));
  }

  /// Internal helper for emitting failure status with error context.
  void _emitFailure(
    EventBase event,
    TState? newState,
    Set<String>? groupsToRebuild,
    Object? error,
    StackTrace? errorStackTrace,
  ) {
    if (_stateManager.isClosed) {
      throw StateError('Cannot emit failure after bloc is closed');
    }

    _logger.log('Emitting failure', context: {
      'type': 'state_emission',
      'status': 'failure',
      'state': '${newState ?? state}',
      'bloc': _blocName,
      'groups': groupsToRebuild?.toString(),
      'event': event.runtimeType.toString(),
      'error': error?.toString(),
    });

    // Apply default groups if not specified
    final groups = groupsToRebuild ?? rebuildAlways;

    // Validate group constraints
    assert(
      !groups.contains('*') || groups.length == 1,
      "Cannot mix '*' with other groups",
    );

    // Merge groups onto the event
    event.groupsToRebuild = {...?event.groupsToRebuild, ...groups};

    // Emit the failure status with error context
    _stateManager.emit(StreamStatus.failure(
      newState ?? state,
      state,
      event,
      error: error,
      errorStackTrace: errorStackTrace,
    ));
  }
}
