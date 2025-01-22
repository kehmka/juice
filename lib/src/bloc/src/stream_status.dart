import 'package:juice/juice.dart';

///
/// StreamStatus States
///
/// `Updating`: Represents a general state transition.
/// `Waiting`: Indicates an async operation in progress.
/// `Canceling`: Indicates an operation is being cancelled.
/// `Failure`: Represents an error encountered during state transition.
///
/// **Best Practices**:
/// - Use `StreamStatus` for transient states (UI feedback, async operations, errors)
/// - Use `BlocState` for persistent application state
///

@immutable
abstract class StreamStatus<TState extends BlocState> {
  final TState state;
  final TState oldState;
  final EventBase? event;

  const StreamStatus(this.state, this.oldState, this.event);

  // Factory constructors for different transient statuses
  factory StreamStatus.updating(
          TState state, TState oldState, EventBase? event) =>
      UpdatingStatus(state, oldState, event);

  factory StreamStatus.waiting(
          TState state, TState oldState, EventBase? event) =>
      WaitingStatus(state, oldState, event);

  factory StreamStatus.canceling(
          TState state, TState oldState, EventBase? event) =>
      CancelingStatus(state, oldState, event);

  factory StreamStatus.failure(
          TState state, TState oldState, EventBase? event) =>
      FailureStatus(state, oldState, event);

  // CopyWith method
  StreamStatus<TState> copyWith({
    TState? state,
    TState? oldState,
    EventBase? event,
  });

  // Pattern matching utility
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

class UpdatingStatus<TState extends BlocState> extends StreamStatus<TState> {
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

class WaitingStatus<TState extends BlocState> extends StreamStatus<TState> {
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

class CancelingStatus<TState extends BlocState> extends StreamStatus<TState> {
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

class FailureStatus<TState extends BlocState> extends StreamStatus<TState> {
  const FailureStatus(super.state, super.oldState, super.event);

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

  String get debugDescription {
    return match(
      updating: (status) => 'Updating: ${status.state}',
      waiting: (_) => 'Waiting...',
      canceling: (_) => 'Canceling...',
      failure: (status) => 'Failure: ${status.state}',
      orElse: (_) => 'Unknown status type',
    );
  }
}

extension StatusChecks<T extends BlocState> on StreamStatus {
  bool matchesState<S extends BlocState>() => this is StreamStatus<S>;

  bool isUpdatingFor<S extends BlocState>() =>
      this is StreamStatus<S> && this is UpdatingStatus;

  bool isWaitingFor<S extends BlocState>() =>
      this is StreamStatus<S> && this is WaitingStatus;

  bool isFailureFor<S extends BlocState>() =>
      this is StreamStatus<S> && this is FailureStatus;

  bool isCancelingFor<S extends BlocState>() =>
      this is StreamStatus<S> && this is CancelingStatus;

  UpdatingStatus<S>? tryCastToUpdating<S extends BlocState>() =>
      this is UpdatingStatus<S> ? this as UpdatingStatus<S> : null;

  WaitingStatus<S>? tryCastToWaiting<S extends BlocState>() =>
      this is WaitingStatus<S> ? this as WaitingStatus<S> : null;

  FailureStatus<S>? tryCastToFailure<S extends BlocState>() =>
      this is FailureStatus<S> ? this as FailureStatus<S> : null;

  CancelingStatus<S>? tryCastToCanceling<S extends BlocState>() =>
      this is CancelingStatus<S> ? this as CancelingStatus<S> : null;

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
