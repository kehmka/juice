import 'dart:math';

import 'package:dio/dio.dart';

import 'interceptor.dart';

/// Implements retry with exponential backoff.
///
/// Respects idempotency rules:
/// - GET, HEAD, PUT, DELETE are retryable by default
/// - POST, PATCH require explicit opt-in with idempotencyKey
///
/// Example:
/// ```dart
/// RetryInterceptor(
///   dio: dio,
///   maxRetries: 3,
///   retryOn: (e) => e.type == DioExceptionType.connectionError,
/// )
/// ```
class RetryInterceptor extends FetchInterceptor {
  /// The Dio instance for retrying requests.
  final Dio dio;

  /// Maximum number of retry attempts.
  final int maxRetries;

  /// Function to compute backoff duration for each attempt.
  final Duration Function(int attempt) backoff;

  /// Function to determine if an error is retryable.
  final bool Function(DioException error) retryOn;

  /// Callback when a retry is about to happen.
  final void Function(int attempt, Duration delay)? onRetry;

  RetryInterceptor({
    required this.dio,
    this.maxRetries = 3,
    Duration Function(int attempt)? backoff,
    bool Function(DioException error)? retryOn,
    this.onRetry,
  })  : backoff = backoff ?? _defaultBackoff,
        retryOn = retryOn ?? _defaultRetryOn;

  /// Default exponential backoff with jitter.
  static Duration _defaultBackoff(int attempt) {
    const base = Duration(milliseconds: 500);
    const maxDelay = Duration(seconds: 30);

    // Exponential: 500ms, 1s, 2s, 4s, ...
    final exponential = base * pow(2, attempt - 1).toInt();

    // Add jitter: ±15%
    final jitter = Random().nextDouble() * 0.3 - 0.15;
    final withJitter = exponential * (1 + jitter);

    // Clamp to max
    if (withJitter > maxDelay) return maxDelay;
    return withJitter;
  }

  /// Default retry conditions.
  static bool _defaultRetryOn(DioException error) {
    // Retry on network errors
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return true;
    }

    // Retry on 5xx (except 501 Not Implemented)
    final statusCode = error.response?.statusCode;
    if (statusCode != null && statusCode >= 500 && statusCode != 501) {
      return true;
    }

    // Retry on 429 Too Many Requests
    if (statusCode == 429) {
      return true;
    }

    return false;
  }

  @override
  int get priority => InterceptorPriority.retry;

  @override
  Future<dynamic> onError(DioException error) async {
    final request = error.requestOptions;
    final attempt = (request.extra['_retryCount'] as int?) ?? 0;

    // Check retry limit
    final maxAttempts = request.extra['maxAttempts'] as int? ?? maxRetries;
    if (attempt >= maxAttempts) {
      return error;
    }

    // Check if retryable
    if (!retryOn(error)) {
      return error;
    }

    // Check idempotency
    if (!_isIdempotent(request)) {
      return error;
    }

    // Compute delay
    Duration delay;
    if (error.response?.statusCode == 429) {
      // Check Retry-After header
      delay = _parseRetryAfter(error.response!) ?? backoff(attempt + 1);
    } else {
      delay = backoff(attempt + 1);
    }

    // Notify callback
    onRetry?.call(attempt + 1, delay);

    // Wait before retry
    await Future<void>.delayed(delay);

    // Increment retry count
    request.extra['_retryCount'] = attempt + 1;

    // Retry the request
    return dio.fetch(request);
  }

  /// Check if request is idempotent and safe to retry.
  bool _isIdempotent(RequestOptions request) {
    final method = request.method.toUpperCase();

    // GET, HEAD, PUT, DELETE are idempotent
    if (['GET', 'HEAD', 'PUT', 'DELETE'].contains(method)) {
      return true;
    }

    // POST, PATCH only if explicitly marked retryable with idempotency key
    if (request.extra['retryable'] == true &&
        request.extra['idempotencyKey'] != null) {
      return true;
    }

    return false;
  }

  /// Parse Retry-After header.
  Duration? _parseRetryAfter(Response response) {
    final retryAfter = response.headers.value('retry-after');
    if (retryAfter == null) return null;

    // Try parsing as seconds
    final seconds = int.tryParse(retryAfter);
    if (seconds != null) {
      return Duration(seconds: seconds);
    }

    // Try parsing as HTTP date
    try {
      final date = HttpDate.parse(retryAfter);
      return date.difference(DateTime.now());
    } catch (_) {
      return null;
    }
  }
}

/// Simple HTTP date parser for Retry-After header.
class HttpDate {
  static DateTime parse(String date) {
    // Simple implementation - production would use full HTTP date parsing
    return DateTime.parse(date);
  }
}
