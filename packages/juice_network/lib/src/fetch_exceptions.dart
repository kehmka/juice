import 'package:flutter/foundation.dart';

import 'request/request_key.dart';

/// Base class for all fetch-related errors.
///
/// Provides structured error information including the request key,
/// status code, and timing information.
@immutable
sealed class FetchError implements Exception {
  /// The request key that failed, if available.
  final RequestKey? requestKey;

  /// HTTP status code, if applicable.
  final int? statusCode;

  /// Time elapsed before the error occurred.
  final Duration? elapsed;

  /// Human-readable error message.
  final String message;

  /// The underlying cause, if any.
  final Object? cause;

  /// Stack trace from the underlying error.
  final StackTrace? stackTrace;

  const FetchError({
    required this.message,
    this.requestKey,
    this.statusCode,
    this.elapsed,
    this.cause,
    this.stackTrace,
  });

  @override
  String toString() => '$runtimeType: $message';
}

/// Network connectivity error - no response received.
@immutable
class NetworkError extends FetchError {
  const NetworkError({
    required super.message,
    super.requestKey,
    super.elapsed,
    super.cause,
    super.stackTrace,
  }) : super(statusCode: null);

  factory NetworkError.noConnection({
    RequestKey? requestKey,
    Duration? elapsed,
    Object? cause,
    StackTrace? stackTrace,
  }) {
    return NetworkError(
      message: 'No network connection',
      requestKey: requestKey,
      elapsed: elapsed,
      cause: cause,
      stackTrace: stackTrace,
    );
  }
}

/// Type of timeout that occurred.
enum TimeoutType {
  /// Connection could not be established.
  connect,

  /// Request data could not be sent.
  send,

  /// Response data was not received.
  receive,
}

/// Request timed out.
@immutable
class TimeoutError extends FetchError {
  /// Type of timeout that occurred.
  final TimeoutType type;

  /// The timeout duration that was exceeded.
  final Duration timeout;

  const TimeoutError({
    required this.type,
    required this.timeout,
    required super.message,
    super.requestKey,
    super.elapsed,
    super.cause,
    super.stackTrace,
  }) : super(statusCode: null);

  factory TimeoutError.connect({
    required Duration timeout,
    RequestKey? requestKey,
    Duration? elapsed,
    Object? cause,
    StackTrace? stackTrace,
  }) {
    return TimeoutError(
      type: TimeoutType.connect,
      timeout: timeout,
      message: 'Connection timed out after $timeout',
      requestKey: requestKey,
      elapsed: elapsed,
      cause: cause,
      stackTrace: stackTrace,
    );
  }

  factory TimeoutError.send({
    required Duration timeout,
    RequestKey? requestKey,
    Duration? elapsed,
    Object? cause,
    StackTrace? stackTrace,
  }) {
    return TimeoutError(
      type: TimeoutType.send,
      timeout: timeout,
      message: 'Send timed out after $timeout',
      requestKey: requestKey,
      elapsed: elapsed,
      cause: cause,
      stackTrace: stackTrace,
    );
  }

  factory TimeoutError.receive({
    required Duration timeout,
    RequestKey? requestKey,
    Duration? elapsed,
    Object? cause,
    StackTrace? stackTrace,
  }) {
    return TimeoutError(
      type: TimeoutType.receive,
      timeout: timeout,
      message: 'Receive timed out after $timeout',
      requestKey: requestKey,
      elapsed: elapsed,
      cause: cause,
      stackTrace: stackTrace,
    );
  }
}

/// Server returned an error status code.
@immutable
class HttpError extends FetchError {
  /// The response body, if available.
  final dynamic responseBody;

  /// Response headers, if available.
  final Map<String, List<String>>? responseHeaders;

  const HttpError({
    required int statusCode,
    required super.message,
    this.responseBody,
    this.responseHeaders,
    super.requestKey,
    super.elapsed,
    super.cause,
    super.stackTrace,
  }) : super(statusCode: statusCode);

  /// Whether this error is retryable (5xx or 429).
  bool get isRetryable {
    final code = statusCode;
    if (code == null) return false;
    return code >= 500 && code != 501 || code == 429;
  }
}

/// Client error (4xx status codes).
@immutable
class ClientError extends HttpError {
  const ClientError({
    required super.statusCode,
    required super.message,
    super.responseBody,
    super.responseHeaders,
    super.requestKey,
    super.elapsed,
    super.cause,
    super.stackTrace,
  });

  factory ClientError.badRequest({
    dynamic responseBody,
    Map<String, List<String>>? responseHeaders,
    RequestKey? requestKey,
    Duration? elapsed,
  }) {
    return ClientError(
      statusCode: 400,
      message: 'Bad request',
      responseBody: responseBody,
      responseHeaders: responseHeaders,
      requestKey: requestKey,
      elapsed: elapsed,
    );
  }

  factory ClientError.unauthorized({
    dynamic responseBody,
    Map<String, List<String>>? responseHeaders,
    RequestKey? requestKey,
    Duration? elapsed,
  }) {
    return ClientError(
      statusCode: 401,
      message: 'Unauthorized',
      responseBody: responseBody,
      responseHeaders: responseHeaders,
      requestKey: requestKey,
      elapsed: elapsed,
    );
  }

  factory ClientError.forbidden({
    dynamic responseBody,
    Map<String, List<String>>? responseHeaders,
    RequestKey? requestKey,
    Duration? elapsed,
  }) {
    return ClientError(
      statusCode: 403,
      message: 'Forbidden',
      responseBody: responseBody,
      responseHeaders: responseHeaders,
      requestKey: requestKey,
      elapsed: elapsed,
    );
  }

  factory ClientError.notFound({
    dynamic responseBody,
    Map<String, List<String>>? responseHeaders,
    RequestKey? requestKey,
    Duration? elapsed,
  }) {
    return ClientError(
      statusCode: 404,
      message: 'Not found',
      responseBody: responseBody,
      responseHeaders: responseHeaders,
      requestKey: requestKey,
      elapsed: elapsed,
    );
  }
}

/// Server error (5xx status codes).
@immutable
class ServerError extends HttpError {
  const ServerError({
    required super.statusCode,
    required super.message,
    super.responseBody,
    super.responseHeaders,
    super.requestKey,
    super.elapsed,
    super.cause,
    super.stackTrace,
  });

  @override
  bool get isRetryable => statusCode != 501;

  factory ServerError.internalError({
    dynamic responseBody,
    Map<String, List<String>>? responseHeaders,
    RequestKey? requestKey,
    Duration? elapsed,
  }) {
    return ServerError(
      statusCode: 500,
      message: 'Internal server error',
      responseBody: responseBody,
      responseHeaders: responseHeaders,
      requestKey: requestKey,
      elapsed: elapsed,
    );
  }

  factory ServerError.badGateway({
    dynamic responseBody,
    Map<String, List<String>>? responseHeaders,
    RequestKey? requestKey,
    Duration? elapsed,
  }) {
    return ServerError(
      statusCode: 502,
      message: 'Bad gateway',
      responseBody: responseBody,
      responseHeaders: responseHeaders,
      requestKey: requestKey,
      elapsed: elapsed,
    );
  }

  factory ServerError.serviceUnavailable({
    dynamic responseBody,
    Map<String, List<String>>? responseHeaders,
    RequestKey? requestKey,
    Duration? elapsed,
  }) {
    return ServerError(
      statusCode: 503,
      message: 'Service unavailable',
      responseBody: responseBody,
      responseHeaders: responseHeaders,
      requestKey: requestKey,
      elapsed: elapsed,
    );
  }
}

/// JSON decode or type conversion failed.
@immutable
class DecodeError extends FetchError {
  /// The expected type.
  final Type expectedType;

  /// The actual value that couldn't be decoded.
  final dynamic actualValue;

  const DecodeError({
    required this.expectedType,
    required this.actualValue,
    required super.message,
    super.requestKey,
    super.elapsed,
    super.cause,
    super.stackTrace,
  }) : super(statusCode: null);

  factory DecodeError.jsonParseFailed({
    required dynamic actualValue,
    RequestKey? requestKey,
    Duration? elapsed,
    Object? cause,
    StackTrace? stackTrace,
  }) {
    return DecodeError(
      expectedType: Map<String, dynamic>,
      actualValue: actualValue,
      message: 'Failed to parse JSON',
      requestKey: requestKey,
      elapsed: elapsed,
      cause: cause,
      stackTrace: stackTrace,
    );
  }

  factory DecodeError.typeMismatch({
    required Type expectedType,
    required dynamic actualValue,
    RequestKey? requestKey,
    Duration? elapsed,
    Object? cause,
    StackTrace? stackTrace,
  }) {
    return DecodeError(
      expectedType: expectedType,
      actualValue: actualValue,
      message: 'Expected $expectedType but got ${actualValue.runtimeType}',
      requestKey: requestKey,
      elapsed: elapsed,
      cause: cause,
      stackTrace: stackTrace,
    );
  }
}

/// Request was cancelled.
@immutable
class CancelledError extends FetchError {
  /// Reason for cancellation.
  final String? reason;

  const CancelledError({
    this.reason,
    super.requestKey,
    super.elapsed,
  }) : super(
          message: reason ?? 'Request cancelled',
          statusCode: null,
        );
}
