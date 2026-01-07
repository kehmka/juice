/// Base exception class for Juice framework errors.
///
/// All Juice-specific exceptions extend this class, enabling consistent
/// error handling and categorization across the application.
///
/// ## Usage
///
/// ```dart
/// try {
///   await fetchData();
/// } on JuiceException catch (e) {
///   if (e.isRetryable) {
///     // Retry the operation
///   }
///   emitFailure(newState: state.copyWith(error: e.message));
/// }
/// ```
///
/// ## Custom Exceptions
///
/// ```dart
/// class MyCustomException extends JuiceException {
///   MyCustomException(String message) : super(message);
///
///   @override
///   bool get isRetryable => false;
/// }
/// ```
abstract class JuiceException implements Exception {
  /// Creates a JuiceException with a message and optional cause.
  const JuiceException(
    this.message, {
    this.cause,
    this.stackTrace,
  });

  /// Human-readable error message.
  final String message;

  /// The underlying error that caused this exception, if any.
  final Object? cause;

  /// The stack trace where this exception occurred.
  final StackTrace? stackTrace;

  /// Whether this error is potentially recoverable by retrying.
  bool get isRetryable;

  /// Whether this is a network-related error.
  bool get isNetworkError => false;

  /// Whether this is a validation error.
  bool get isValidationError => false;

  /// Whether this is a timeout error.
  bool get isTimeoutError => false;

  @override
  String toString() => '$runtimeType: $message';
}

/// Exception for network-related errors.
///
/// Use this for HTTP failures, connection issues, DNS errors, etc.
///
/// ```dart
/// try {
///   final response = await http.get(url);
///   if (response.statusCode >= 500) {
///     throw NetworkException(
///       'Server error',
///       statusCode: response.statusCode,
///     );
///   }
/// } on SocketException catch (e) {
///   throw NetworkException('No internet connection', cause: e);
/// }
/// ```
class NetworkException extends JuiceException {
  /// Creates a NetworkException.
  const NetworkException(
    super.message, {
    this.statusCode,
    super.cause,
    super.stackTrace,
  });

  /// HTTP status code, if applicable.
  final int? statusCode;

  /// Network errors are generally retryable.
  @override
  bool get isRetryable => true;

  @override
  bool get isNetworkError => true;

  /// Whether this is a client error (4xx status code).
  bool get isClientError =>
      statusCode != null && statusCode! >= 400 && statusCode! < 500;

  /// Whether this is a server error (5xx status code).
  bool get isServerError => statusCode != null && statusCode! >= 500;

  @override
  String toString() {
    if (statusCode != null) {
      return 'NetworkException: $message (status: $statusCode)';
    }
    return 'NetworkException: $message';
  }
}

/// Exception for validation errors.
///
/// Use this for input validation failures, constraint violations, etc.
///
/// ```dart
/// if (email.isEmpty) {
///   throw ValidationException('Email is required', field: 'email');
/// }
/// if (!emailRegex.hasMatch(email)) {
///   throw ValidationException('Invalid email format', field: 'email');
/// }
/// ```
class ValidationException extends JuiceException {
  /// Creates a ValidationException.
  const ValidationException(
    super.message, {
    this.field,
    this.errors,
    super.cause,
    super.stackTrace,
  });

  /// The field that failed validation, if applicable.
  final String? field;

  /// Multiple validation errors, keyed by field name.
  final Map<String, String>? errors;

  /// Validation errors are not retryable without user action.
  @override
  bool get isRetryable => false;

  @override
  bool get isValidationError => true;

  @override
  String toString() {
    if (field != null) {
      return 'ValidationException: $message (field: $field)';
    }
    return 'ValidationException: $message';
  }
}

/// Exception for timeout errors.
///
/// Use this when operations exceed their allowed time.
///
/// ```dart
/// try {
///   await operation.timeout(Duration(seconds: 30));
/// } on TimeoutException catch (e) {
///   throw JuiceTimeoutException(
///     'Operation timed out',
///     duration: Duration(seconds: 30),
///     cause: e,
///   );
/// }
/// ```
class JuiceTimeoutException extends JuiceException {
  /// Creates a JuiceTimeoutException.
  const JuiceTimeoutException(
    super.message, {
    this.duration,
    super.cause,
    super.stackTrace,
  });

  /// The timeout duration that was exceeded.
  final Duration? duration;

  /// Timeouts are generally retryable.
  @override
  bool get isRetryable => true;

  @override
  bool get isTimeoutError => true;

  @override
  String toString() {
    if (duration != null) {
      return 'JuiceTimeoutException: $message (after ${duration!.inSeconds}s)';
    }
    return 'JuiceTimeoutException: $message';
  }
}

/// Exception for cancelled operations.
///
/// Use this when a [CancellableEvent] is cancelled during execution.
///
/// ```dart
/// if (event.isCancelled) {
///   throw CancelledException('User cancelled the operation');
/// }
/// ```
class CancelledException extends JuiceException {
  /// Creates a CancelledException.
  const CancelledException(
    super.message, {
    super.cause,
    super.stackTrace,
  });

  /// Cancelled operations are not retryable.
  @override
  bool get isRetryable => false;

  @override
  String toString() => 'CancelledException: $message';
}

/// Exception for state-related errors.
///
/// Use this for invalid state transitions or state access errors.
///
/// ```dart
/// if (bloc.isClosed) {
///   throw StateException('Cannot send events to a closed bloc');
/// }
/// ```
class StateException extends JuiceException {
  /// Creates a StateException.
  const StateException(
    super.message, {
    super.cause,
    super.stackTrace,
  });

  /// State errors are generally not retryable.
  @override
  bool get isRetryable => false;

  @override
  String toString() => 'StateException: $message';
}

/// Exception for configuration or initialization errors.
///
/// Use this for missing dependencies, invalid configuration, etc.
///
/// ```dart
/// if (!BlocScope.isRegistered<MyBloc>()) {
///   throw ConfigurationException('MyBloc is not registered');
/// }
/// ```
class ConfigurationException extends JuiceException {
  /// Creates a ConfigurationException.
  const ConfigurationException(
    super.message, {
    super.cause,
    super.stackTrace,
  });

  /// Configuration errors are not retryable.
  @override
  bool get isRetryable => false;

  @override
  String toString() => 'ConfigurationException: $message';
}
