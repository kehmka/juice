import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:juice/juice.dart';

import '../cache/cache_policy.dart';
import '../cache/wire_cache_record.dart';
import '../fetch_bloc.dart';
import '../fetch_events.dart';
import '../fetch_exceptions.dart';
import '../fetch_state.dart';
import '../request/request_coalescer.dart';
import '../request/request_key.dart';
import '../request/request_status.dart';

/// Base mixin for HTTP request use cases.
mixin RequestUseCaseMixin<TEvent extends EventBase>
    on BlocUseCase<FetchBloc, TEvent> {
  /// Build full URL with query params.
  String buildUrl(String url, Map<String, dynamic>? queryParams) {
    if (queryParams == null || queryParams.isEmpty) return url;

    final uri = Uri.parse(url);
    final newUri = uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        ...queryParams.map((k, v) => MapEntry(k, v.toString())),
      },
    );
    return newUri.toString();
  }

  /// Get auth scope for cache/coalescing key.
  ///
  /// Priority:
  /// 1. AuthIdentityProvider on FetchBloc (recommended for interceptor-injected auth)
  /// 2. Explicit headers passed to the request (legacy/fallback)
  ///
  /// When using AuthInterceptor, the provider returns a user-specific identifier
  /// ensuring cache isolation between users.
  String? getAuthScope(Map<String, String>? headers) {
    // Prefer auth identity provider (safe for interceptor-injected auth)
    final identity = bloc.authIdentityProvider?.call();
    if (identity != null) {
      return identity;
    }

    // Fallback: detect from explicit headers (only safe if auth is passed directly)
    final authHeader =
        headers?['Authorization'] ?? headers?['authorization'];
    if (authHeader == null) return null;

    // Return generic type indicator - NOT user-specific
    // This is only safe when headers are passed directly, not via interceptor
    if (authHeader.startsWith('Bearer ')) return 'bearer';
    if (authHeader.startsWith('Basic ')) return 'basic';
    return 'auth';
  }

  /// Execute HTTP request with caching and coalescing.
  ///
  /// Nullable [cachePolicy], [ttl], and [maxAttempts] are resolved from
  /// [FetchConfig] defaults. For mutation methods (POST, PUT, PATCH, DELETE),
  /// pass the appropriate method-specific default for [methodDefaultCachePolicy].
  Future<void> executeRequest({
    required String method,
    required String url,
    required Map<String, dynamic>? queryParams,
    required Map<String, String>? headers,
    required Object? body,
    required CachePolicy? cachePolicy,
    required CachePolicy methodDefaultCachePolicy,
    required Duration? ttl,
    required bool cacheAuthResponses,
    required bool forceCache,
    required bool allowStaleOnError,
    required bool retryable,
    required int? maxAttempts,
    required String? idempotencyKey,
    required dynamic Function(dynamic)? decode,
    required String? scope,
    required String? variant,
    required RequestKey? keyOverride,
    required Set<String>? groupsToRebuild,
  }) async {
    // Resolve config defaults
    final config = bloc.state.config;
    final effectiveCachePolicy =
        cachePolicy ?? methodDefaultCachePolicy;
    final effectiveTtl = ttl ?? config.defaultTtl;
    final effectiveMaxAttempts = maxAttempts ?? config.defaultMaxRetries;
    // Validate
    if (retryable &&
        (method == 'POST' || method == 'PATCH') &&
        idempotencyKey == null) {
      emitFailure(
        newState: bloc.state,
        error: ArgumentError('Retryable POST/PATCH requires idempotencyKey'),
      );
      return;
    }

    // Compute request key
    final fullUrl = buildUrl(url, queryParams);
    final key = keyOverride ??
        RequestKey.from(
          method: method,
          url: fullUrl,
          body: body,
          headers: headers,
          authScope: getAuthScope(headers),
          variant: variant,
        );

    final groups = groupsToRebuild ?? {FetchGroups.request(key.canonical)};
    final startTime = DateTime.now();

    try {
      // Check cache
      if (effectiveCachePolicy.shouldCheckCache) {
        final cached = await _checkCache(key, effectiveCachePolicy, decode);
        if (cached != null) {
          _emitCacheHit(key, cached, groups);

          if (effectiveCachePolicy == CachePolicy.staleWhileRevalidate) {
            _refreshInBackground(
              method: method,
              key: key,
              headers: headers,
              body: body,
              decode: decode,
              ttl: effectiveTtl,
              cacheAuthResponses: cacheAuthResponses,
              forceCache: forceCache,
              groups: groups,
            );
          }
          return;
        }
        _emitCacheMiss();
      }

      // Cache-only with miss = error
      if (effectiveCachePolicy == CachePolicy.cacheOnly) {
        throw CancelledError(
          reason: 'Cache miss with cacheOnly policy',
          requestKey: key,
        );
      }

      // Check coalescing
      if (bloc.coalescer.isInflight(key)) {
        _emitCoalesced();
        final response = await bloc.coalescer.getInflight(key)!;
        _handleSuccess(key, response, decode, startTime, groups);
        return;
      }

      // Acquire concurrency slot (waits if at limit)
      await bloc.acquireConcurrencySlot();

      try {
        // Mark inflight
        _markInflight(key, scope, groups);

        // Execute with retry logic
        final result = await _executeWithRetry(
          method: method,
          url: url,
          queryParams: queryParams,
          headers: headers,
          body: body,
          key: key,
          retryable: retryable,
          maxAttempts: effectiveMaxAttempts,
          idempotencyKey: idempotencyKey,
        );

        // Emit coalesced stat if this request joined an existing one
        if (result.wasCoalesced) {
          _emitCoalesced();
        }

        // Cache response
        await _cacheResponse(
          key,
          result.response,
          effectiveCachePolicy,
          effectiveTtl,
          cacheAuthResponses,
          forceCache,
          url,
          headers,
        );

        // Handle success
        _handleSuccess(key, result.response, decode, startTime, groups);
      } finally {
        // Always release concurrency slot
        bloc.releaseConcurrencySlot();
      }
    } catch (e, stackTrace) {
      // Try stale cache on error
      if (allowStaleOnError && effectiveCachePolicy != CachePolicy.networkOnly) {
        final stale = await bloc.cacheManager.getStale(key);
        if (stale != null) {
          try {
            final decoded = _decodeFromCache(stale, decode, key);
            _emitSuccess(key, decoded, groups);
            return;
          } on DecodeError {
            // Stale cache decode failed - fall through to error handling
          }
        }
      }

      _handleError(key, e, stackTrace, groups);
    }
  }

  Future<dynamic> _checkCache(
    RequestKey key,
    CachePolicy policy,
    dynamic Function(dynamic)? decode,
  ) async {
    final record = await bloc.cacheManager.get(key);
    if (record == null) return null;

    if (policy == CachePolicy.staleWhileRevalidate) {
      return _decodeFromCache(record, decode, key);
    }

    if (record.isExpired) return null;
    return _decodeFromCache(record, decode, key);
  }

  /// Decode cached response data.
  ///
  /// Returns the decoded data, or throws [DecodeError] on failure.
  dynamic _decodeFromCache(
    WireCacheRecord record,
    dynamic Function(dynamic)? decode,
    RequestKey key,
  ) {
    // Get raw data based on content-type (JSON/text/bytes)
    dynamic rawData;
    try {
      rawData = record.bodyData;
    } on FormatException catch (e, st) {
      throw DecodeError.jsonParseFailed(
        actualValue: record.bodyString,
        requestKey: key,
        cause: e,
        stackTrace: st,
      );
    }

    // Apply user decoder if provided
    if (decode != null) {
      try {
        return decode(rawData);
      } catch (e, st) {
        throw DecodeError(
          expectedType: dynamic,
          actualValue: rawData,
          message: 'Decode function failed: $e',
          requestKey: key,
          cause: e,
          stackTrace: st,
        );
      }
    }

    return rawData;
  }

  void _emitCacheHit(RequestKey key, dynamic data, Set<String> groups) {
    emitUpdate(
      newState: bloc.state.copyWith(
        stats: bloc.state.stats.withCacheHit(),
      ),
      groupsToRebuild: {FetchGroups.statsGroup, ...groups},
    );
  }

  void _emitCacheMiss() {
    emitUpdate(
      newState: bloc.state.copyWith(
        stats: bloc.state.stats.withCacheMiss(),
      ),
      groupsToRebuild: {FetchGroups.statsGroup},
    );
  }

  void _emitCoalesced() {
    emitUpdate(
      newState: bloc.state.copyWith(
        stats: bloc.state.stats.withCoalesced(),
      ),
      groupsToRebuild: {FetchGroups.statsGroup},
    );
  }

  void _emitBytesSent(int bytes) {
    if (bytes <= 0) return;
    emitUpdate(
      newState: bloc.state.copyWith(
        stats: bloc.state.stats.withBytesSent(bytes),
      ),
      groupsToRebuild: {FetchGroups.statsGroup},
    );
  }

  /// Estimate body size in bytes.
  int _estimateBodySize(Object? body) {
    if (body == null) return 0;
    if (body is String) return body.length;
    if (body is List<int>) return body.length;
    // For maps/objects, estimate via JSON encoding
    try {
      return jsonEncode(body).length;
    } catch (_) {
      return 0;
    }
  }

  void _markInflight(RequestKey key, String? scope, Set<String> groups) {
    final status = RequestStatus.inflight(
      key: key,
      scope: scope,
      cancelToken: CancelToken(),
    );

    emitWaiting(
      newState: bloc.state.copyWith(
        activeRequests: {...bloc.state.activeRequests, key.canonical: status},
        inflightCount: bloc.state.inflightCount + 1,
      ),
      groupsToRebuild: {FetchGroups.inflight, ...groups},
    );
  }

  Future<Response<dynamic>> _executeNetwork({
    required String method,
    required String url,
    required Map<String, dynamic>? queryParams,
    required Map<String, String>? headers,
    required Object? body,
    required RequestKey key,
    required bool retryable,
    required int maxAttempts,
    required String? idempotencyKey,
  }) {
    final status = bloc.state.activeRequests[key.canonical];

    // Track bytes sent (body size)
    final bytesSent = _estimateBodySize(body);
    if (bytesSent > 0) {
      _emitBytesSent(bytesSent);
    }

    // Build extra map for RetryInterceptor
    final extra = <String, dynamic>{
      'retryable': retryable,
      'maxAttempts': maxAttempts,
      if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
    };

    return bloc.dio.request<dynamic>(
      url,
      data: body,
      queryParameters: queryParams,
      options: Options(
        method: method,
        headers: headers,
        extra: extra,
      ),
      cancelToken: status?.cancelToken,
    );
  }

  /// Execute network request with retry logic.
  ///
  /// Retries on:
  /// - Network errors (connection, timeout)
  /// - 5xx server errors
  /// - 429 Too Many Requests
  ///
  /// Uses exponential backoff: 1s, 2s, 4s, etc.
  ///
  /// Returns a [CoalesceResult] indicating whether this request was coalesced.
  Future<CoalesceResult> _executeWithRetry({
    required String method,
    required String url,
    required Map<String, dynamic>? queryParams,
    required Map<String, String>? headers,
    required Object? body,
    required RequestKey key,
    required bool retryable,
    required int maxAttempts,
    required String? idempotencyKey,
  }) async {
    // Use coalescing for the retry loop
    return bloc.coalescer.coalesce(key, () async {
      int attempts = 0;
      Object? lastError;
      StackTrace? lastStackTrace;

      while (attempts < maxAttempts) {
        attempts++;

        try {
          final response = await _executeNetwork(
            method: method,
            url: url,
            queryParams: queryParams,
            headers: headers,
            body: body,
            key: key,
            retryable: retryable,
            maxAttempts: maxAttempts,
            idempotencyKey: idempotencyKey,
          );

          // Check for retryable status codes
          if (retryable && _isRetryableStatusCode(response.statusCode)) {
            lastError = DioException(
              requestOptions: response.requestOptions,
              response: response,
              type: DioExceptionType.badResponse,
              message: 'Retryable status code: ${response.statusCode}',
            );
            lastStackTrace = StackTrace.current;

            if (attempts < maxAttempts) {
              _emitRetry();
              await _backoff(attempts);
              continue;
            }
          }

          return response;
        } on DioException catch (e, st) {
          lastError = e;
          lastStackTrace = st;

          // Check if error is retryable
          if (!retryable || !_isRetryableError(e)) {
            rethrow;
          }

          // Check if cancelled
          if (e.type == DioExceptionType.cancel) {
            rethrow;
          }

          // Retry if more attempts available
          if (attempts < maxAttempts) {
            _emitRetry();
            await _backoff(attempts);
            continue;
          }

          rethrow;
        }
      }

      // Should not reach here, but throw last error if we do
      Error.throwWithStackTrace(
        lastError ?? StateError('Retry exhausted'),
        lastStackTrace ?? StackTrace.current,
      );
    });
  }

  /// Check if HTTP status code is retryable.
  bool _isRetryableStatusCode(int? statusCode) {
    if (statusCode == null) return false;
    // Retry on 5xx server errors and 429 rate limit
    return statusCode >= 500 || statusCode == 429;
  }

  /// Check if Dio exception is retryable.
  bool _isRetryableError(DioException e) {
    return switch (e.type) {
      // Network errors are retryable
      DioExceptionType.connectionTimeout => true,
      DioExceptionType.sendTimeout => true,
      DioExceptionType.receiveTimeout => true,
      DioExceptionType.connectionError => true,
      // Bad response - check status code
      DioExceptionType.badResponse =>
        _isRetryableStatusCode(e.response?.statusCode),
      // These are not retryable
      DioExceptionType.cancel => false,
      DioExceptionType.badCertificate => false,
      DioExceptionType.unknown => false,
    };
  }

  /// Exponential backoff: 1s, 2s, 4s, 8s, max 30s
  Future<void> _backoff(int attempt) async {
    final delay = Duration(
      milliseconds: (1000 * (1 << (attempt - 1))).clamp(1000, 30000),
    );
    await Future<void>.delayed(delay);
  }

  void _emitRetry() {
    emitUpdate(
      newState: bloc.state.copyWith(
        stats: bloc.state.stats.withRetry(),
      ),
      groupsToRebuild: {FetchGroups.statsGroup},
    );
  }

  Future<void> _cacheResponse(
    RequestKey key,
    Response<dynamic> response,
    CachePolicy cachePolicy,
    Duration? ttl,
    bool cacheAuthResponses,
    bool forceCache,
    String url,
    Map<String, String>? headers,
  ) async {
    if (!cachePolicy.shouldCache) return;

    final hasAuth = headers?.containsKey('Authorization') ?? false;
    if (hasAuth && !cacheAuthResponses) return;

    if (_isSensitiveEndpoint(url) && !forceCache) return;

    final cacheControl = response.headers.value('cache-control');
    if (cacheControl != null &&
        cacheControl.contains('no-store') &&
        !forceCache) {
      return;
    }

    final vary = response.headers.value('vary');
    if (vary == '*') return;

    final record = WireCacheRecord.fromResponse(response, key.canonical, ttl: ttl);
    await bloc.cacheManager.put(key, record);
  }

  bool _isSensitiveEndpoint(String url) {
    const patterns = ['/auth/', '/login', '/token', '/oauth/'];
    return patterns.any((p) => url.contains(p));
  }

  void _handleSuccess(
    RequestKey key,
    Response<dynamic> response,
    dynamic Function(dynamic)? decode,
    DateTime startTime,
    Set<String> groups,
  ) {
    final decoded = _decodeResponse(response, decode, key);
    final elapsed = DateTime.now().difference(startTime);
    final bytesReceived = response.data?.toString().length ?? 0;

    _emitSuccess(key, decoded, groups, elapsed, bytesReceived);
  }

  /// Decode response data based on content-type.
  ///
  /// - JSON content-type → parse as JSON
  /// - Other → pass raw data to decoder
  ///
  /// Throws [DecodeError] on JSON parse failure or decoder exception.
  dynamic _decodeResponse(
    Response<dynamic> response,
    dynamic Function(dynamic)? decode,
    RequestKey key,
  ) {
    final contentType =
        response.headers.value('content-type')?.toLowerCase() ?? '';
    final isJson = contentType.contains('application/json') ||
        contentType.contains('+json');

    dynamic rawData;
    if (response.data is String && isJson) {
      // JSON content-type with String response → parse JSON
      try {
        rawData = jsonDecode(response.data as String);
      } on FormatException catch (e, st) {
        throw DecodeError.jsonParseFailed(
          actualValue: response.data,
          requestKey: key,
          cause: e,
          stackTrace: st,
        );
      }
    } else {
      // Non-JSON or already-parsed data → use as-is
      rawData = response.data;
    }

    // Apply user decoder if provided
    if (decode != null) {
      try {
        return decode(rawData);
      } catch (e, st) {
        throw DecodeError(
          expectedType: dynamic,
          actualValue: rawData,
          message: 'Decode function failed: $e',
          requestKey: key,
          cause: e,
          stackTrace: st,
        );
      }
    }

    return rawData;
  }

  void _emitSuccess(
    RequestKey key,
    dynamic decoded,
    Set<String> groups, [
    Duration? elapsed,
    int bytesReceived = 0,
  ]) {
    final newRequests = {...bloc.state.activeRequests}..remove(key.canonical);
    var stats = bloc.state.stats;
    if (elapsed != null) {
      stats = stats.withSuccess(bytesReceived, elapsed);
    }

    emitUpdate(
      newState: bloc.state.copyWith(
        activeRequests: newRequests,
        inflightCount: (bloc.state.inflightCount - 1).clamp(0, 999999),
        stats: stats,
      ),
      groupsToRebuild: {FetchGroups.inflight, FetchGroups.statsGroup, ...groups},
    );
  }

  void _handleError(
    RequestKey key,
    Object error,
    StackTrace stackTrace,
    Set<String> groups,
  ) {
    final fetchError = _transformError(error, key, stackTrace);
    final newRequests = {...bloc.state.activeRequests}..remove(key.canonical);

    emitFailure(
      newState: bloc.state.copyWith(
        activeRequests: newRequests,
        inflightCount: (bloc.state.inflightCount - 1).clamp(0, 999999),
        lastError: fetchError,
        stats: bloc.state.stats.withFailure(),
      ),
      groupsToRebuild: {
        FetchGroups.inflight,
        FetchGroups.error,
        FetchGroups.statsGroup,
        ...groups,
      },
      error: fetchError,
      errorStackTrace: stackTrace,
    );
  }

  FetchError _transformError(Object error, RequestKey key, StackTrace stack) {
    if (error is FetchError) return error;

    if (error is DioException) {
      return _transformDioError(error, key, stack);
    }

    return NetworkError(
      message: error.toString(),
      requestKey: key,
      cause: error,
      stackTrace: stack,
    );
  }

  FetchError _transformDioError(DioException e, RequestKey key, StackTrace stack) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return TimeoutError.connect(
          timeout: bloc.state.config.connectTimeout,
          requestKey: key,
          cause: e,
          stackTrace: stack,
        );
      case DioExceptionType.sendTimeout:
        return TimeoutError.send(
          timeout: bloc.state.config.sendTimeout,
          requestKey: key,
          cause: e,
          stackTrace: stack,
        );
      case DioExceptionType.receiveTimeout:
        return TimeoutError.receive(
          timeout: bloc.state.config.receiveTimeout,
          requestKey: key,
          cause: e,
          stackTrace: stack,
        );
      case DioExceptionType.connectionError:
        return NetworkError.noConnection(
          requestKey: key,
          cause: e,
          stackTrace: stack,
        );
      case DioExceptionType.cancel:
        return CancelledError(reason: e.message, requestKey: key);
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode ?? 0;
        final body = e.response?.data;
        final hdrs = e.response?.headers.map;
        if (code >= 400 && code < 500) {
          return ClientError(
            statusCode: code,
            message: 'Client error: $code',
            responseBody: body,
            responseHeaders: hdrs,
            requestKey: key,
            cause: e,
            stackTrace: stack,
          );
        } else if (code >= 500) {
          return ServerError(
            statusCode: code,
            message: 'Server error: $code',
            responseBody: body,
            responseHeaders: hdrs,
            requestKey: key,
            cause: e,
            stackTrace: stack,
          );
        }
        return HttpError(
          statusCode: code,
          message: 'HTTP error: $code',
          responseBody: body,
          responseHeaders: hdrs,
          requestKey: key,
          cause: e,
          stackTrace: stack,
        );
      default:
        return NetworkError(
          message: e.message ?? 'Unknown error',
          requestKey: key,
          cause: e,
          stackTrace: stack,
        );
    }
  }

  void _refreshInBackground({
    required String method,
    required RequestKey key,
    required Map<String, String>? headers,
    required Object? body,
    required dynamic Function(dynamic)? decode,
    required Duration? ttl,
    required bool cacheAuthResponses,
    required bool forceCache,
    required Set<String> groups,
  }) {
    bloc.coalescer
        .coalesce(
          key,
          () => bloc.dio.request<dynamic>(
            key.url,
            data: body,
            options: Options(method: method, headers: headers),
          ),
        )
        .then((result) async {
          final record =
              WireCacheRecord.fromResponse(result.response, key.canonical, ttl: ttl);
          await bloc.cacheManager.put(key, record);

          emitUpdate(
            newState: bloc.state,
            groupsToRebuild: groups,
          );
        })
        .catchError((_) {
          // Background refresh failure is silent
        });
  }
}

/// GET request use case.
class GetUseCase extends BlocUseCase<FetchBloc, GetEvent>
    with RequestUseCaseMixin<GetEvent> {
  @override
  Future<void> execute(GetEvent event) => executeRequest(
        method: 'GET',
        url: event.url,
        queryParams: event.queryParams,
        headers: event.headers,
        body: null,
        cachePolicy: event.cachePolicy,
        methodDefaultCachePolicy: bloc.state.config.defaultCachePolicy,
        ttl: event.ttl,
        cacheAuthResponses: event.cacheAuthResponses,
        forceCache: event.forceCache,
        allowStaleOnError: event.allowStaleOnError,
        retryable: event.retryable,
        maxAttempts: event.maxAttempts,
        idempotencyKey: null,
        decode: event.decode,
        scope: event.scope,
        variant: event.variant,
        keyOverride: event.keyOverride,
        groupsToRebuild: event.groupsToRebuild,
      );
}

/// POST request use case.
class PostUseCase extends BlocUseCase<FetchBloc, PostEvent>
    with RequestUseCaseMixin<PostEvent> {
  @override
  Future<void> execute(PostEvent event) => executeRequest(
        method: 'POST',
        url: event.url,
        queryParams: event.queryParams,
        headers: event.headers,
        body: event.body,
        cachePolicy: event.cachePolicy,
        methodDefaultCachePolicy: CachePolicy.networkOnly, // Mutations don't cache
        ttl: event.ttl,
        cacheAuthResponses: event.cacheAuthResponses,
        forceCache: event.forceCache,
        allowStaleOnError: event.allowStaleOnError,
        retryable: event.retryable,
        maxAttempts: event.maxAttempts,
        idempotencyKey: event.idempotencyKey,
        decode: event.decode,
        scope: event.scope,
        variant: event.variant,
        keyOverride: event.keyOverride,
        groupsToRebuild: event.groupsToRebuild,
      );
}

/// PUT request use case.
class PutUseCase extends BlocUseCase<FetchBloc, PutEvent>
    with RequestUseCaseMixin<PutEvent> {
  @override
  Future<void> execute(PutEvent event) => executeRequest(
        method: 'PUT',
        url: event.url,
        queryParams: event.queryParams,
        headers: event.headers,
        body: event.body,
        cachePolicy: event.cachePolicy,
        methodDefaultCachePolicy: CachePolicy.networkOnly, // Mutations don't cache
        ttl: event.ttl,
        cacheAuthResponses: event.cacheAuthResponses,
        forceCache: event.forceCache,
        allowStaleOnError: event.allowStaleOnError,
        retryable: event.retryable,
        maxAttempts: event.maxAttempts,
        idempotencyKey: event.idempotencyKey,
        decode: event.decode,
        scope: event.scope,
        variant: event.variant,
        keyOverride: event.keyOverride,
        groupsToRebuild: event.groupsToRebuild,
      );
}

/// PATCH request use case.
class PatchUseCase extends BlocUseCase<FetchBloc, PatchEvent>
    with RequestUseCaseMixin<PatchEvent> {
  @override
  Future<void> execute(PatchEvent event) => executeRequest(
        method: 'PATCH',
        url: event.url,
        queryParams: event.queryParams,
        headers: event.headers,
        body: event.body,
        cachePolicy: event.cachePolicy,
        methodDefaultCachePolicy: CachePolicy.networkOnly, // Mutations don't cache
        ttl: event.ttl,
        cacheAuthResponses: event.cacheAuthResponses,
        forceCache: event.forceCache,
        allowStaleOnError: event.allowStaleOnError,
        retryable: event.retryable,
        maxAttempts: event.maxAttempts,
        idempotencyKey: event.idempotencyKey,
        decode: event.decode,
        scope: event.scope,
        variant: event.variant,
        keyOverride: event.keyOverride,
        groupsToRebuild: event.groupsToRebuild,
      );
}

/// DELETE request use case.
class DeleteUseCase extends BlocUseCase<FetchBloc, DeleteEvent>
    with RequestUseCaseMixin<DeleteEvent> {
  @override
  Future<void> execute(DeleteEvent event) => executeRequest(
        method: 'DELETE',
        url: event.url,
        queryParams: event.queryParams,
        headers: event.headers,
        body: null,
        cachePolicy: event.cachePolicy,
        methodDefaultCachePolicy: CachePolicy.networkOnly, // Mutations don't cache
        ttl: null,
        cacheAuthResponses: false,
        forceCache: false,
        allowStaleOnError: false,
        retryable: event.retryable,
        maxAttempts: event.maxAttempts,
        idempotencyKey: null,
        decode: event.decode,
        scope: event.scope,
        variant: event.variant,
        keyOverride: event.keyOverride,
        groupsToRebuild: event.groupsToRebuild,
      );
}

/// HEAD request use case.
class HeadUseCase extends BlocUseCase<FetchBloc, HeadEvent>
    with RequestUseCaseMixin<HeadEvent> {
  @override
  Future<void> execute(HeadEvent event) => executeRequest(
        method: 'HEAD',
        url: event.url,
        queryParams: event.queryParams,
        headers: event.headers,
        body: null,
        cachePolicy: CachePolicy.networkOnly,
        methodDefaultCachePolicy: CachePolicy.networkOnly, // HEAD doesn't cache
        ttl: null,
        cacheAuthResponses: false,
        forceCache: false,
        allowStaleOnError: false,
        retryable: event.retryable,
        maxAttempts: null,
        idempotencyKey: null,
        decode: null,
        scope: event.scope,
        variant: null,
        keyOverride: null,
        groupsToRebuild: event.groupsToRebuild,
      );
}
