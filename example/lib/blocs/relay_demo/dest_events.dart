import 'package:juice/juice.dart';

/// Sent by a `changes` reaction when the source's counter changes.
class CounterChangedEvent extends EventBase {
  final int counter;

  CounterChangedEvent({required this.counter});
}

/// Sent by a `becomes` reaction when the source becomes busy.
class SourceBusyEvent extends EventBase {}

/// Sent by a `becomes` reaction when the source gets an error.
class SourceFailedEvent extends EventBase {
  final String? errorMessage;

  SourceFailedEvent({this.errorMessage});
}

/// Clear the log
class ClearLogEvent extends EventBase {}
