import 'package:dio/dio.dart';

import 'interceptor.dart';

/// Logs requests and responses for debugging.
///
/// Example:
/// ```dart
/// LoggingInterceptor(
///   logger: (msg) => debugPrint(msg),
///   logBody: true,
///   logHeaders: false,
/// )
/// ```
class LoggingInterceptor extends FetchInterceptor {
  /// Function to output log messages.
  final void Function(String message) logger;

  /// Whether to log request/response bodies.
  final bool logBody;

  /// Whether to log headers.
  final bool logHeaders;

  /// Whether to log errors.
  final bool logErrors;

  /// Maximum body length to log (truncates if exceeded).
  final int maxBodyLength;

  /// Whether to redact sensitive headers.
  final bool redactSensitiveHeaders;

  /// Headers to redact (values replaced with [REDACTED]).
  final Set<String> sensitiveHeaders;

  LoggingInterceptor({
    required this.logger,
    this.logBody = false,
    this.logHeaders = false,
    this.logErrors = true,
    this.maxBodyLength = 1000,
    this.redactSensitiveHeaders = true,
    this.sensitiveHeaders = const {
      'authorization',
      'cookie',
      'set-cookie',
      'x-api-key',
    },
  });

  @override
  int get priority => InterceptorPriority.logging;

  @override
  Future<RequestOptions> onRequest(RequestOptions options) async {
    final buffer = StringBuffer();
    buffer.writeln('→ ${options.method} ${options.uri}');

    if (logHeaders) {
      buffer.writeln('  Headers:');
      options.headers.forEach((key, value) {
        final displayValue = _redactIfSensitive(key, value.toString());
        buffer.writeln('    $key: $displayValue');
      });
    }

    if (logBody && options.data != null) {
      final bodyStr = _truncateBody(options.data.toString());
      buffer.writeln('  Body: $bodyStr');
    }

    logger(buffer.toString().trimRight());
    return options;
  }

  @override
  Future<Response<dynamic>> onResponse(Response<dynamic> response) async {
    final buffer = StringBuffer();
    final elapsed = _getElapsed(response.requestOptions);
    buffer.writeln(
        '← ${response.statusCode} ${response.requestOptions.uri} ($elapsed)');

    if (logHeaders) {
      buffer.writeln('  Headers:');
      response.headers.forEach((name, values) {
        final displayValue = _redactIfSensitive(name, values.join(', '));
        buffer.writeln('    $name: $displayValue');
      });
    }

    if (logBody && response.data != null) {
      final bodyStr = _truncateBody(response.data.toString());
      buffer.writeln('  Body: $bodyStr');
    }

    logger(buffer.toString().trimRight());
    return response;
  }

  @override
  Future<dynamic> onError(DioException error) async {
    if (!logErrors) return error;

    final buffer = StringBuffer();
    final elapsed = _getElapsed(error.requestOptions);
    buffer.writeln('✗ ${error.type.name} ${error.requestOptions.uri} ($elapsed)');

    if (error.response != null) {
      buffer.writeln('  Status: ${error.response!.statusCode}');
      if (logBody && error.response!.data != null) {
        final bodyStr = _truncateBody(error.response!.data.toString());
        buffer.writeln('  Body: $bodyStr');
      }
    }

    buffer.writeln('  Error: ${error.message}');

    logger(buffer.toString().trimRight());
    return error;
  }

  String _redactIfSensitive(String key, String value) {
    if (!redactSensitiveHeaders) return value;
    if (sensitiveHeaders.contains(key.toLowerCase())) {
      return '[REDACTED]';
    }
    return value;
  }

  String _truncateBody(String body) {
    if (body.length <= maxBodyLength) return body;
    return '${body.substring(0, maxBodyLength)}... (truncated)';
  }

  String _getElapsed(RequestOptions options) {
    final startTime = options.extra['_startTime'] as DateTime?;
    if (startTime == null) return '?ms';
    final elapsed = DateTime.now().difference(startTime);
    return '${elapsed.inMilliseconds}ms';
  }
}

/// Interceptor to add timing information to requests.
///
/// Use with [LoggingInterceptor] to show request duration.
class TimingInterceptor extends FetchInterceptor {
  @override
  int get priority => InterceptorPriority.logging - 1; // Before logging

  @override
  Future<RequestOptions> onRequest(RequestOptions options) async {
    options.extra['_startTime'] = DateTime.now();
    return options;
  }
}
