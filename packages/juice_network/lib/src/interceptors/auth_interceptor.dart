import 'package:dio/dio.dart';

import 'interceptor.dart';

/// Injects authorization headers from a token provider.
///
/// Example:
/// ```dart
/// AuthInterceptor(
///   tokenProvider: () => authBloc.state.accessToken,
/// )
/// ```
class AuthInterceptor extends FetchInterceptor {
  /// Function to get the current token.
  /// Returns null if no token is available.
  final Future<String?> Function() tokenProvider;

  /// Header name for the token.
  final String headerName;

  /// Prefix before the token value (e.g., 'Bearer ').
  final String prefix;

  /// Whether to skip adding auth for certain paths.
  final bool Function(String path)? skipAuth;

  AuthInterceptor({
    required this.tokenProvider,
    this.headerName = 'Authorization',
    this.prefix = 'Bearer ',
    this.skipAuth,
  });

  @override
  int get priority => InterceptorPriority.auth;

  @override
  Future<RequestOptions> onRequest(RequestOptions options) async {
    // Check if auth should be skipped for this path
    if (skipAuth != null && skipAuth!(options.path)) {
      return options;
    }

    // Don't override if already set
    if (options.headers.containsKey(headerName)) {
      return options;
    }

    final token = await tokenProvider();
    if (token != null && token.isNotEmpty) {
      options.headers[headerName] = '$prefix$token';
    }

    return options;
  }
}

/// API key authentication interceptor.
///
/// Example:
/// ```dart
/// ApiKeyInterceptor(
///   apiKey: 'your-api-key',
///   headerName: 'X-API-Key',
/// )
/// ```
class ApiKeyInterceptor extends FetchInterceptor {
  /// The API key value.
  final String apiKey;

  /// Header name for the API key.
  final String headerName;

  /// Whether to add as query parameter instead of header.
  final bool asQueryParam;

  /// Query parameter name (if asQueryParam is true).
  final String queryParamName;

  ApiKeyInterceptor({
    required this.apiKey,
    this.headerName = 'X-API-Key',
    this.asQueryParam = false,
    this.queryParamName = 'api_key',
  });

  @override
  int get priority => InterceptorPriority.auth;

  @override
  Future<RequestOptions> onRequest(RequestOptions options) async {
    if (asQueryParam) {
      options.queryParameters[queryParamName] = apiKey;
    } else {
      options.headers[headerName] = apiKey;
    }
    return options;
  }
}
