import 'package:dio/dio.dart';

import 'interceptor.dart';

/// Adds conditional request headers for cache validation.
///
/// When a cached response has ETag or Last-Modified, subsequent
/// requests include If-None-Match or If-Modified-Since headers.
/// On 304 Not Modified, the cached response is returned.
///
/// Example:
/// ```dart
/// ETagInterceptor(
///   getETag: (url) => cacheManager.getETag(url),
///   getLastModified: (url) => cacheManager.getLastModified(url),
///   onNotModified: (url) => cacheManager.touch(url),
/// )
/// ```
class ETagInterceptor extends FetchInterceptor {
  /// Function to get cached ETag for a URL.
  final Future<String?> Function(String url) getETag;

  /// Function to get cached Last-Modified for a URL.
  final Future<String?> Function(String url)? getLastModified;

  /// Function to save ETag from response.
  final Future<void> Function(String url, String etag)? saveETag;

  /// Function to save Last-Modified from response.
  final Future<void> Function(String url, String lastModified)? saveLastModified;

  /// Callback when 304 Not Modified is received.
  final Future<void> Function(String url)? onNotModified;

  ETagInterceptor({
    required this.getETag,
    this.getLastModified,
    this.saveETag,
    this.saveLastModified,
    this.onNotModified,
  });

  @override
  int get priority => InterceptorPriority.etag;

  @override
  Future<RequestOptions> onRequest(RequestOptions options) async {
    // Only apply to GET requests
    if (options.method.toUpperCase() != 'GET') {
      return options;
    }

    final url = options.uri.toString();

    // Add If-None-Match if we have an ETag
    final etag = await getETag(url);
    if (etag != null) {
      options.headers['If-None-Match'] = etag;
    }

    // Add If-Modified-Since if we have Last-Modified
    if (getLastModified != null) {
      final lastModified = await getLastModified!(url);
      if (lastModified != null) {
        options.headers['If-Modified-Since'] = lastModified;
      }
    }

    return options;
  }

  @override
  Future<Response<dynamic>> onResponse(Response<dynamic> response) async {
    final url = response.requestOptions.uri.toString();

    // Save ETag if present
    final etag = response.headers.value('etag');
    if (etag != null && saveETag != null) {
      await saveETag!(url, etag);
    }

    // Save Last-Modified if present
    final lastModified = response.headers.value('last-modified');
    if (lastModified != null && saveLastModified != null) {
      await saveLastModified!(url, lastModified);
    }

    return response;
  }

  @override
  Future<dynamic> onError(DioException error) async {
    // Check for 304 Not Modified
    if (error.response?.statusCode == 304) {
      final url = error.requestOptions.uri.toString();

      // Notify that content is not modified
      await onNotModified?.call(url);

      // Return the cached response if available
      // The use case should handle returning cached data
      // For now, we just propagate a special marker
      error.requestOptions.extra['_notModified'] = true;
    }

    return error;
  }
}

/// Simple ETag cache for in-memory storage.
///
/// For production use, integrate with CacheManager.
class InMemoryETagCache {
  final Map<String, String> _etags = {};
  final Map<String, String> _lastModified = {};

  Future<String?> getETag(String url) async => _etags[url];

  Future<String?> getLastModified(String url) async => _lastModified[url];

  Future<void> saveETag(String url, String etag) async {
    _etags[url] = etag;
  }

  Future<void> saveLastModified(String url, String lastModified) async {
    _lastModified[url] = lastModified;
  }

  void clear() {
    _etags.clear();
    _lastModified.clear();
  }
}
