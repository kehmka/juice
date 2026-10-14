import 'package:logger/web.dart' show Level;

import '../bloc_state.dart';
import '../bloc_event.dart';
import '../stream_status.dart';
import '../juice_logger.dart';
import '../../../ui/src/widget_support.dart';
import 'state_manager.dart';
import 'type_names.dart';
import '../telemetry.dart';

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
      if (JuiceLoggerConfig.logs(Level.info)) {
        _logger.record(JuiceTelemetry(
          JuiceTelemetryKind.emissionSkipped,
          bloc: _blocName,
          event: typeName(event.runtimeType),
        ));
      }
      return;
    }
    _emit(_Kind.update, event, newState, groups);
  }

  /// Emits a waiting status.
  ///
  /// Used to indicate an async operation is in progress.
  void emitWaiting(EventBase event, TState? newState, Set<String>? groups) {
    _emit(_Kind.waiting, event, newState, groups);
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
    _emit(_Kind.failure, event, newState, groups,
        error: error, errorStackTrace: errorStackTrace);
  }

  /// Emits a canceling status.
  ///
  /// Used to indicate an operation was cancelled.
  void emitCancel(EventBase event, TState? newState, Set<String>? groups) {
    _emit(_Kind.cancel, event, newState, groups);
  }

  /// Re-emits the current status carrying [event] — no state change, no
  /// groups: a signal to listeners that watch events.
  void emitEvent(EventBase event) {
    if (_droppedAfterClose('event', event)) return;
    _stateManager.emit(_stateManager.current.copyWith(event: event));
  }

  /// The close fence. A use case still running when its bloc closes (the
  /// user left mid-fetch) must not crash on its next emit — that emit is
  /// dropped, and logged as `emission_after_close` so it stays visible.
  bool _droppedAfterClose(String statusName, EventBase event, {Object? error}) {
    if (!_stateManager.isClosed) return false;
    _logger.record(JuiceTelemetry(
      JuiceTelemetryKind.emissionAfterClose,
      status: statusName,
      bloc: _blocName,
      event: typeName(event.runtimeType),
      error: error,
    ));
    return true;
  }

  void _emit(
    _Kind kind,
    EventBase event,
    TState? newState,
    Set<String>? groupsToRebuild, {
    Object? error,
    StackTrace? errorStackTrace,
  }) {
    if (_droppedAfterClose(kind.name, event, error: error)) return;

    // A failure emission is never chatter: it is logged whatever the floor.
    if (kind == _Kind.failure || JuiceLoggerConfig.logs(Level.info)) {
      _logger.record(JuiceTelemetry(
        JuiceTelemetryKind.stateEmitted,
        status: kind.name,
        // Live objects: a logger that prints stringifies them itself; one
        // that drops the entry pays nothing.
        state: newState ?? state,
        bloc: _blocName,
        groups: groupsToRebuild,
        event: typeName(event.runtimeType),
        error: error,
      ));
    }

    final groups = groupsToRebuild ?? rebuildAlways;
    assert(
      !groups.contains('*') || groups.length == 1,
      "Cannot mix '*' with other groups",
    );
    // The event accumulates the groups of every emit made for it. The first
    // emit adopts the caller's set as is (no copy); a later emit merges.
    final existing = event.groupsToRebuild;
    event.groupsToRebuild = existing == null || existing.isEmpty
        ? groups
        : {...existing, ...groups};

    final current = state;
    final next = newState ?? current;
    _stateManager.emit(switch (kind) {
      _Kind.update => UpdatingStatus<TState>(next, current, event),
      _Kind.waiting => WaitingStatus<TState>(next, current, event),
      _Kind.cancel => CancelingStatus<TState>(next, current, event),
      _Kind.failure => FailureStatus<TState>(next, current, event,
          error: error, errorStackTrace: errorStackTrace),
    });
  }
}

/// The status an emit produces; `name` is the telemetry `status` value.
enum _Kind { update, waiting, failure, cancel }
