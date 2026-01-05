import 'package:juice/juice.dart';

/// Increment the counter.
/// Demonstrates: skipIfSame deduplication option.
class ShowcaseIncrementEvent extends EventBase {}

/// Decrement the counter.
class ShowcaseDecrementEvent extends EventBase {}

/// Simulate an API call that can succeed or fail.
/// Demonstrates: sendAndWait, FailureStatus error context, JuiceException.
class SimulateApiCallEvent extends EventBase {
  /// If true, the API call will fail with a NetworkException.
  final bool shouldFail;

  SimulateApiCallEvent({this.shouldFail = false});
}

/// Update the message (demonstrates skipIfSame).
class UpdateMessageEvent extends EventBase {
  final String message;

  UpdateMessageEvent(this.message);
}

/// Trigger a validation error.
/// Demonstrates: ValidationException.
class ValidateInputEvent extends EventBase {
  final String input;

  ValidateInputEvent(this.input);
}

/// Clear any error state.
class ClearErrorEvent extends EventBase {}

/// Reset all state to initial values.
class ShowcaseResetEvent extends EventBase {}
