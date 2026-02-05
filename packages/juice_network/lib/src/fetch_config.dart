import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'cache/cache_policy.dart';

/// Provides a user-specific identity for cache and coalescing keys.
///
/// **IMPORTANT**: If you use an AuthInterceptor to inject authentication headers,
/// you MUST provide an [AuthIdentityProvider] to ensure cache/coalescing safety.
/// Without this, responses may be incorrectly shared between different users.
///
/// The returned string should be:
/// - Unique per user (e.g., user ID, hashed email, session ID)
/// - Stable for the duration of the user's session
/// - null when no user is authenticated (requests will use unauthenticated cache)
///
/// Example:
/// ```dart
/// FetchBloc(
///   storageBloc: storageBloc,
///   authIdentityProvider: () => authBloc.state.userId,
/// )
/// ```
typedef AuthIdentityProvider = String? Function();

/// Platform-neutral configuration for FetchBloc.
///
/// These values work identically across all platforms (mobile, desktop, web).
@immutable
class FetchConfig {
  /// Base URL for all requests.
  /// Example: 'https://api.example.com'
  final String? baseUrl;

  /// Default timeout for establishing connection.
  final Duration connectTimeout;

  /// Default timeout for receiving response data.
  final Duration receiveTimeout;

  /// Default timeout for sending request data.
  final Duration sendTimeout;

  /// Default cache policy for requests.
  final CachePolicy defaultCachePolicy;

  /// Default TTL for cached responses.
  /// If null, uses server Cache-Control headers or no expiry.
  final Duration? defaultTtl;

  /// Maximum cache size in bytes.
  /// Default: 50 MB
  final int maxCacheSize;

  /// Maximum concurrent requests.
  /// Requests beyond this are queued.
  final int maxConcurrentRequests;

  /// Default headers for all requests.
  final Map<String, String> defaultHeaders;

  /// Whether to follow redirects.
  final bool followRedirects;

  /// Maximum redirects to follow.
  final int maxRedirects;

  /// Default retry attempts for retryable requests.
  final int defaultMaxRetries;

  /// Whether to validate response status codes.
  /// If true, 4xx/5xx responses throw HttpError.
  final bool validateStatus;

  const FetchConfig({
    this.baseUrl,
    this.connectTimeout = const Duration(seconds: 30),
    this.receiveTimeout = const Duration(seconds: 30),
    this.sendTimeout = const Duration(seconds: 30),
    this.defaultCachePolicy = CachePolicy.networkFirst,
    this.defaultTtl,
    this.maxCacheSize = 50 * 1024 * 1024, // 50 MB
    this.maxConcurrentRequests = 10,
    this.defaultHeaders = const {},
    this.followRedirects = true,
    this.maxRedirects = 5,
    this.defaultMaxRetries = 3,
    this.validateStatus = true,
  });

  /// Create a copy with modified values.
  FetchConfig copyWith({
    String? baseUrl,
    Duration? connectTimeout,
    Duration? receiveTimeout,
    Duration? sendTimeout,
    CachePolicy? defaultCachePolicy,
    Duration? defaultTtl,
    int? maxCacheSize,
    int? maxConcurrentRequests,
    Map<String, String>? defaultHeaders,
    bool? followRedirects,
    int? maxRedirects,
    int? defaultMaxRetries,
    bool? validateStatus,
  }) {
    return FetchConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      connectTimeout: connectTimeout ?? this.connectTimeout,
      receiveTimeout: receiveTimeout ?? this.receiveTimeout,
      sendTimeout: sendTimeout ?? this.sendTimeout,
      defaultCachePolicy: defaultCachePolicy ?? this.defaultCachePolicy,
      defaultTtl: defaultTtl ?? this.defaultTtl,
      maxCacheSize: maxCacheSize ?? this.maxCacheSize,
      maxConcurrentRequests:
          maxConcurrentRequests ?? this.maxConcurrentRequests,
      defaultHeaders: defaultHeaders ?? this.defaultHeaders,
      followRedirects: followRedirects ?? this.followRedirects,
      maxRedirects: maxRedirects ?? this.maxRedirects,
      defaultMaxRetries: defaultMaxRetries ?? this.defaultMaxRetries,
      validateStatus: validateStatus ?? this.validateStatus,
    );
  }
}

/// Platform-specific configuration options.
///
/// These options only apply to certain platforms and are safely ignored
/// on unsupported platforms.
@immutable
class PlatformConfig {
  // === Mobile/Desktop Only ===

  /// Certificate pinning configuration.
  /// Ignored on web (browser manages TLS).
  final CertificatePinConfig? certificatePinning;

  /// Custom HTTP adapter (e.g., Http2Adapter for HTTP/2).
  /// Ignored on web.
  final HttpClientAdapter? httpAdapter;

  /// Proxy configuration.
  /// Ignored on web.
  final ProxyConfig? proxy;

  // === Web Only ===

  /// Include credentials (cookies) in CORS requests.
  /// Ignored on mobile/desktop.
  final bool withCredentials;

  const PlatformConfig({
    this.certificatePinning,
    this.httpAdapter,
    this.proxy,
    this.withCredentials = false,
  });

  /// Whether running on web platform.
  static bool get isWeb => kIsWeb;
}

/// Certificate pinning configuration for mobile/desktop.
@immutable
class CertificatePinConfig {
  /// Host to pin certificates for.
  final String host;

  /// SHA-256 fingerprints of allowed certificates.
  final List<String> sha256Fingerprints;

  const CertificatePinConfig({
    required this.host,
    required this.sha256Fingerprints,
  });
}

/// Proxy configuration for mobile/desktop.
@immutable
class ProxyConfig {
  /// Proxy host.
  final String host;

  /// Proxy port.
  final int port;

  /// Username for proxy authentication.
  final String? username;

  /// Password for proxy authentication.
  final String? password;

  const ProxyConfig({
    required this.host,
    required this.port,
    this.username,
    this.password,
  });

  /// Proxy URL for Dio configuration.
  String get proxyUrl {
    if (username != null && password != null) {
      return 'http://$username:$password@$host:$port';
    }
    return 'http://$host:$port';
  }
}
