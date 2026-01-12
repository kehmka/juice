import 'dart:async';

import 'package:dio/dio.dart';

import 'interceptor.dart';

/// Handles 401 responses with token refresh using singleflight pattern.
///
/// This prevents "401 storm" where N concurrent requests all trigger
/// N refresh attempts. Instead, only one refresh happens and all
/// waiting requests share the result.
///
/// Example:
/// ```dart
/// RefreshTokenInterceptor(
///   dio: dio,
///   refreshToken: () => authBloc.refreshAccessToken(),
///   onRefreshFailed: () => authBloc.send(LogoutEvent()),
///   getAccessToken: () => authBloc.state.accessToken,
/// )
/// ```
class RefreshTokenInterceptor extends FetchInterceptor {
  /// The Dio instance for retrying requests.
  final Dio dio;

  /// Function to refresh the token. Returns new access token or null on failure.
  final Future<String?> Function() refreshToken;

  /// Called when token refresh fails (e.g., to trigger logout).
  final Future<void> Function()? onRefreshFailed;

  /// Function to get the current access token for retry.
  final Future<String?> Function()? getAccessToken;

  /// Header name for authorization.
  final String headerName;

  /// Prefix before the token value.
  final String prefix;

  /// Status codes that trigger a refresh attempt.
  final Set<int> refreshOnStatusCodes;

  /// In-flight refresh completer for singleflight pattern.
  Completer<String?>? _refreshInFlight;

  /// Lock to prevent concurrent refresh initiation.
  bool _isRefreshing = false;

  RefreshTokenInterceptor({
    required this.dio,
    required this.refreshToken,
    this.onRefreshFailed,
    this.getAccessToken,
    this.headerName = 'Authorization',
    this.prefix = 'Bearer ',
    this.refreshOnStatusCodes = const {401},
  });

  @override
  int get priority => InterceptorPriority.refreshToken;

  @override
  Future<dynamic> onError(DioException error) async {
    // Check if this is a refresh-triggering status code
    final statusCode = error.response?.statusCode;
    if (statusCode == null || !refreshOnStatusCodes.contains(statusCode)) {
      return error;
    }

    // Don't try to refresh if this was already a retry
    if (error.requestOptions.extra['_isRetryAfterRefresh'] == true) {
      return error;
    }

    // Singleflight: if refresh is already in progress, wait for it
    if (_refreshInFlight != null) {
      try {
        final newToken = await _refreshInFlight!.future;
        if (newToken != null) {
          return _retryRequest(error.requestOptions, newToken);
        }
      } catch (_) {
        // Refresh failed, propagate original error
      }
      return error;
    }

    // Prevent concurrent refresh initiation
    if (_isRefreshing) {
      return error;
    }

    // Start refresh
    _isRefreshing = true;
    _refreshInFlight = Completer<String?>();

    try {
      final newToken = await refreshToken();

      if (newToken == null) {
        _refreshInFlight!.complete(null);
        await onRefreshFailed?.call();
        return error;
      }

      _refreshInFlight!.complete(newToken);
      return _retryRequest(error.requestOptions, newToken);
    } catch (e) {
      _refreshInFlight!.completeError(e);
      await onRefreshFailed?.call();
      return error;
    } finally {
      _isRefreshing = false;
      _refreshInFlight = null;
    }
  }

  /// Retry the failed request with a new token.
  Future<Response<dynamic>> _retryRequest(
    RequestOptions options,
    String newToken,
  ) async {
    // Mark as retry to prevent infinite loop
    options.extra['_isRetryAfterRefresh'] = true;

    // Update the authorization header
    options.headers[headerName] = '$prefix$newToken';

    // Retry the request
    return dio.fetch(options);
  }
}
