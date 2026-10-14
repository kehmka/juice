class BlocErrorHandler {
  // Allow configurable error reporting
  final void Function(String message, {Object? error, StackTrace? stackTrace})?
      onError;

  // Allow configurable logging
  final void Function(String message)? logger;

  const BlocErrorHandler({
    this.onError,
    this.logger,
  });

  void handleError(String message, {Object? error, StackTrace? stackTrace}) {
    // Log the error if logger is provided
    logger?.call(message);

    // Report error if handler provided. The error itself is already on the
    // logger as a `blocError` entry (error and stack trace included), so
    // the handler prints nothing of its own.
    onError?.call(message, error: error, stackTrace: stackTrace);
  }
}

// Specific bloc exceptions
class JuiceBlocException implements Exception {
  final String message;
  final Object? error;
  final StackTrace? stackTrace;

  JuiceBlocException(this.message, {this.error, this.stackTrace});

  @override
  String toString() =>
      'BlocException: $message${error != null ? '\nError: $error' : ''}';
}

class NoEventHandlerException extends JuiceBlocException {
  final Type blocType;
  final Type eventType;

  NoEventHandlerException(this.blocType, this.eventType)
      : super('No handler found for bloc $blocType and event: $eventType');
}
