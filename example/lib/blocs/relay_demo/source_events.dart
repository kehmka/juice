import 'package:juice/juice.dart';

/// Increment the counter
class IncrementSourceEvent extends EventBase {}

/// Decrement the counter
class DecrementSourceEvent extends EventBase {}

/// Simulate an async operation (shows waiting state)
class SimulateAsyncEvent extends EventBase {}

/// Simulate an error condition
class SimulateErrorEvent extends EventBase {}

/// Reset everything
class ResetSourceEvent extends EventBase {}
