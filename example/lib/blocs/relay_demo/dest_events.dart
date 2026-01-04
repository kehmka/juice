import 'package:juice/juice.dart';

/// Event sent by StateRelay when source state changes
class StateRelayedEvent extends EventBase {
  final int counter;

  StateRelayedEvent({required this.counter});
}

/// Event sent by StatusRelay when source is updating
class StatusUpdatingEvent extends EventBase {
  final int counter;

  StatusUpdatingEvent({required this.counter});
}

/// Event sent by StatusRelay when source is waiting (async in progress)
class StatusWaitingEvent extends EventBase {}

/// Event sent by StatusRelay when source has failed
class StatusFailedEvent extends EventBase {
  final String? errorMessage;

  StatusFailedEvent({this.errorMessage});
}

/// Clear the log
class ClearLogEvent extends EventBase {}
