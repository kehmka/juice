import 'package:juice/juice.dart';

/// Represents the current status of a bloc's state stream.
///
/// [StreamStatus] wraps state changes with metadata about the type of change:
/// - [UpdatingStatus]: Normal state transition (success)
/// - [WaitingStatus]: Async operation in progress (loading)
/// - [CancelingStatus]: Operation was cancelled
/// - [FailureStatus]: Operation failed with an error
///
/// ## Usage in Widgets
///
/// ```dart
/// @override
/// Widget onBuild(BuildContext context, StreamStatus status) {
///   if (status is WaitingStatus) {
///     return CircularProgressIndicator();
///   }
///   if (status is FailureStatus) {
///     return Text('Error occurred');
///   }
///   return Text('Count: ${bloc.state.count}');
/// }
/// ```
///
/// ## Pattern Matching
///
/// Use [when] for exhaustive pattern matching:
///
/// ```dart
/// status.when(
///   updating: (state, oldState, event) => Text('$state'),
///   waiting: (state, oldState, event) => CircularProgressIndicator(),
///   failure: (state, oldState, event) => Text('Error'),
///   canceling: (state, oldState, event) => Text('Cancelled'),
/// );
/// ```
///
/// ## Best Practices
///
/// - Use [StreamStatus] for transient UI states (loading, error feedback)
/// - Use [BlocState] for persistent application data
/// - Check status type before accessing state in UI
@immutable
abstract class StreamStatus<TState extends BlocState> {
  /// The current state value.
  final TState state;

  /// The previous state value before this status change.
  final TState oldState;

  /// The event that triggered this status change, if any.
  final EventBase? event;

  /// Creates a StreamStatus with the given state values and event.
  const StreamStatus(this.state, this.oldState, this.event);

  /// Creates an [UpdatingStatus] indicating a successful state transition.
  factory StreamStatus.updating(
          TState state, TState oldState, EventBase? event) =>
      UpdatingStatus(state, oldState, event);

  /// Creates a [WaitingStatus] indicating an async operation in progress.
  factory StreamStatus.waiting(
          TState state, TState oldState, EventBase? event) =>
      WaitingStatus(state, oldState, event);

  /// Creates a [CancelingStatus] indicating an operation was cancelled.
  factory StreamStatus.canceling(
          TState state, TState oldState, EventBase? event) =>
      CancelingStatus(state, oldState, event);

  /// Creates a [FailureStatus] indicating an operation failed.
  ///
  /// [error] - The error that caused the failure.
  /// [errorStackTrace] - The stack trace where the error occurred.
  factory StreamStatus.failure(
    TState state,
    TState oldState,
    EventBase? event, {
    Object? error,
    StackTrace? errorStackTrace,
  }) =>
      FailureStatus(
        state,
        oldState,
        event,
        error: error,
        errorStackTrace: errorStackTrace,
      );

  /// Creates a copy of this status with optionally overridden values.
  StreamStatus<TState> copyWith({
    TState? state,
    TState? oldState,
    EventBase? event,
  });

  /// Pattern matches on the status type and executes the corresponding callback.
  ///
  /// All callbacks are required, ensuring exhaustive handling of all status types.
  R when<R>({
    required R Function(TState state, TState oldState, EventBase? event)
        updating,
    required R Function(TState state, TState oldState, EventBase? event)
        waiting,
    required R Function(TState state, TState oldState, EventBase? event)
        canceling,
    required R Function(TState state, TState oldState, EventBase? event)
        failure,
  });

  @override
  bool operator ==(Object other) =>
      other is StreamStatus<TState> &&
      runtimeType == other.runtimeType &&
      state == other.state &&
      oldState == other.oldState &&
      event == other.event;

  @override
  int get hashCode => Object.hash(state, oldState, event);
}

/// Represents a successful state transition.
///
/// This is the most common status type, indicating that a use case completed
/// successfully and the state has been updated.
///
/// Example:
/// ```dart
/// if (status is UpdatingStatus) {
///   // Safe to display state data
///   return Text(bloc.state.data);
/// }
/// ```
class UpdatingStatus<TState extends BlocState> extends StreamStatus<TState> {
  /// Creates an updating status with the given state values.
  const UpdatingStatus(super.state, super.oldState, super.event);

  @override
  StreamStatus<TState> copyWith({
    TState? state,
    TState? oldState,
    EventBase? event,
  }) {
    return UpdatingStatus(
      state ?? this.state,
      oldState ?? this.oldState,
      event ?? this.event,
    );
  }

  @override
  R when<R>({
    required R Function(TState state, TState oldState, EventBase? event)
        updating,
    required R Function(TState state, TState oldState, EventBase? event)
        waiting,
    required R Function(TState state, TState oldState, EventBase? event)
        canceling,
    required R Function(TState state, TState oldState, EventBase? event)
        failure,
  }) {
    return updating(state, oldState, event);
  }
}

/// Represents an async operation in progress.
///
/// Use this status to show loading indicators while data is being fetched
/// or processed. The state may contain partial or placeholder data.
///
/// Example:
/// ```dart
/// if (status is WaitingStatus) {
///   return CircularProgressIndicator();
/// }
/// ```
class WaitingStatus<TState extends BlocState> extends StreamStatus<TState> {
  /// Creates a waiting status with the given state values.
  const WaitingStatus(super.state, super.oldState, super.event);

  @override
  StreamStatus<TState> copyWith({
    TState? state,
    TState? oldState,
    EventBase? event,
  }) {
    return WaitingStatus(
      state ?? this.state,
      oldState ?? this.oldState,
      event ?? this.event,
    );
  }

  @override
  R when<R>({
    required R Function(TState state, TState oldState, EventBase? event)
        updating,
    required R Function(TState state, TState oldState, EventBase? event)
        waiting,
    required R Function(TState state, TState oldState, EventBase? event)
        canceling,
    required R Function(TState state, TState oldState, EventBase? event)
        failure,
  }) {
    return waiting(state, oldState, event);
  }
}

/// Represents an operation that was cancelled.
///
/// Used when a [CancellableEvent] is cancelled during execution.
/// The UI can use this to show cancellation feedback or restore previous state.
///
/// Example:
/// ```dart
/// if (status is CancelingStatus) {
///   return Text('Operation cancelled');
/// }
/// ```
class CancelingStatus<TState extends BlocState> extends StreamStatus<TState> {
  /// Creates a canceling status with the given state values.
  const CancelingStatus(super.state, super.oldState, super.event);

  @override
  StreamStatus<TState> copyWith({
    TState? state,
    TState? oldState,
    EventBase? event,
  }) {
    return CancelingStatus(
      state ?? this.state,
      oldState ?? this.oldState,
      event ?? this.event,
    );
  }

  @override
  R when<R>({
    required R Function(TState state, TState oldState, EventBase? event)
        updating,
    required R Function(TState state, TState oldState, EventBase? event)
        waiting,
    required R Function(TState state, TState oldState, EventBase? event)
        canceling,
    required R Function(TState state, TState oldState, EventBase? event)
        failure,
  }) {
    return canceling(state, oldState, event);
  }
}

/// Represents an operation that failed with an error.
///
/// Use this status to show error messages and retry options.
/// The state typically contains the last known good state or error details.
///
/// The [error] and [errorStackTrace] properties provide access to the
/// underlying exception details when available.
///
/// Example:
/// ```dart
/// if (status is FailureStatus) {
///   final failure = status as FailureStatus;
///   return Column(
///     children: [
///       Text(failure.error?.toString() ?? 'Something went wrong'),
///       ElevatedButton(
///         onPressed: () => bloc.send(RetryEvent()),
///         child: Text('Retry'),
///       ),
///     ],
///   );
/// }
/// ```
class FailureStatus<TState extends BlocState> extends StreamStatus<TState> {
  /// Creates a failure status with the given state values.
  ///
  /// [error] - The error that caused the failure, if available.
  /// [errorStackTrace] - The stack trace where the error occurred.
  const FailureStatus(
    super.state,
    super.oldState,
    super.event, {
    this.error,
    this.errorStackTrace,
  });

  /// The error that caused this failure, if available.
  ///
  /// This can be any object, but is typically an [Exception] or [Error].
  /// Use this to display error details to the user or for logging.
  final Object? error;

  /// The stack trace where the error occurred, if available.
  ///
  /// Useful for debugging and error reporting.
  final StackTrace? errorStackTrace;

  @override
  StreamStatus<TState> copyWith({
    TState? state,
    TState? oldState,
    EventBase? event,
  }) {
    return FailureStatus(
      state ?? this.state,
      oldState ?? this.oldState,
      event ?? this.event,
      error: error,
      errorStackTrace: errorStackTrace,
    );
  }

  /// Creates a copy with updated error information.
  FailureStatus<TState> copyWithError({
    TState? state,
    TState? oldState,
    EventBase? event,
    Object? error,
    StackTrace? errorStackTrace,
  }) {
    return FailureStatus(
      state ?? this.state,
      oldState ?? this.oldState,
      event ?? this.event,
      error: error ?? this.error,
      errorStackTrace: errorStackTrace ?? this.errorStackTrace,
    );
  }

  @override
  R when<R>({
    required R Function(TState state, TState oldState, EventBase? event)
        updating,
    required R Function(TState state, TState oldState, EventBase? event)
        waiting,
    required R Function(TState state, TState oldState, EventBase? event)
        canceling,
    required R Function(TState state, TState oldState, EventBase? event)
        failure,
  }) {
    return failure(state, oldState, event);
  }

  /// Returns a human-readable description of this status for debugging.
  String get debugDescription {
    final errorInfo = error != null ? ' (error: $error)' : '';
    return match(
      updating: (status) => 'Updating: ${status.state}',
      waiting: (_) => 'Waiting...',
      canceling: (_) => 'Canceling...',
      failure: (status) => 'Failure: ${status.state}$errorInfo',
      orElse: (_) => 'Unknown status type',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FailureStatus<TState> &&
      super == other &&
      error == other.error;

  @override
  int get hashCode => Object.hash(super.hashCode, error);
}

/// Extension methods for type-safe status checking and casting.
///
/// These methods provide safe ways to check and cast [StreamStatus] instances
/// to specific types without manual type checking.
///
/// ## Type Checking
///
/// ```dart
/// if (status.isWaitingFor<MyState>()) {
///   // Show loading indicator
/// }
/// ```
///
/// ## Safe Casting
///
/// ```dart
/// final updating = status.tryCastToUpdating<MyState>();
/// if (updating != null) {
///   // Work with UpdatingStatus<MyState>
/// }
/// ```
///
/// ## Pattern Matching
///
/// ```dart
/// final result = status.match<MyState, Widget>(
///   updating: (s) => Text(s.state.data),
///   waiting: (s) => CircularProgressIndicator(),
///   canceling: (s) => Text('Cancelled'),
///   failure: (s) => Text('Error'),
///   orElse: (s) => SizedBox.shrink(),
/// );
/// ```
extension StatusChecks<T extends BlocState> on StreamStatus {
  /// Returns true if this status is for the given state type.
  bool matchesState<S extends BlocState>() => this is StreamStatus<S>;

  /// Returns true if this is an [UpdatingStatus] for the given state type.
  bool isUpdatingFor<S extends BlocState>() =>
      this is StreamStatus<S> && this is UpdatingStatus;

  /// Returns true if this is a [WaitingStatus] for the given state type.
  bool isWaitingFor<S extends BlocState>() =>
      this is StreamStatus<S> && this is WaitingStatus;

  /// Returns true if this is a [FailureStatus] for the given state type.
  bool isFailureFor<S extends BlocState>() =>
      this is StreamStatus<S> && this is FailureStatus;

  /// Returns true if this is a [CancelingStatus] for the given state type.
  bool isCancelingFor<S extends BlocState>() =>
      this is StreamStatus<S> && this is CancelingStatus;

  /// Attempts to cast this to [UpdatingStatus] for the given state type.
  /// Returns null if the cast is not valid.
  UpdatingStatus<S>? tryCastToUpdating<S extends BlocState>() =>
      this is UpdatingStatus<S> ? this as UpdatingStatus<S> : null;

  /// Attempts to cast this to [WaitingStatus] for the given state type.
  /// Returns null if the cast is not valid.
  WaitingStatus<S>? tryCastToWaiting<S extends BlocState>() =>
      this is WaitingStatus<S> ? this as WaitingStatus<S> : null;

  /// Attempts to cast this to [FailureStatus] for the given state type.
  /// Returns null if the cast is not valid.
  FailureStatus<S>? tryCastToFailure<S extends BlocState>() =>
      this is FailureStatus<S> ? this as FailureStatus<S> : null;

  /// Attempts to cast this to [CancelingStatus] for the given state type.
  /// Returns null if the cast is not valid.
  CancelingStatus<S>? tryCastToCanceling<S extends BlocState>() =>
      this is CancelingStatus<S> ? this as CancelingStatus<S> : null;

  /// Type-safe pattern matching with an optional fallback.
  ///
  /// Unlike [StreamStatus.when], this method includes an [orElse] callback
  /// for handling unmatched types.
  R match<S extends BlocState, R>({
    required R Function(UpdatingStatus<S>) updating,
    required R Function(WaitingStatus<S>) waiting,
    required R Function(CancelingStatus<S>) canceling,
    required R Function(FailureStatus<S>) failure,
    required R Function(StreamStatus)? orElse,
  }) {
    if (isUpdatingFor<S>()) return updating(this as UpdatingStatus<S>);
    if (isWaitingFor<S>()) return waiting(this as WaitingStatus<S>);
    if (isCancelingFor<S>()) return canceling(this as CancelingStatus<S>);
    if (isFailureFor<S>()) return failure(this as FailureStatus<S>);
    if (orElse != null) return orElse(this);
    throw ArgumentError('Unhandled status type: $runtimeType');
  }
}
