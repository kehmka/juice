import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:juice/juice.dart';

import '../cache/cache_policy.dart';
import '../cache/wire_cache_record.dart';
import '../fetch_bloc.dart';
import '../fetch_events.dart';
import '../fetch_exceptions.dart';
import '../fetch_state.dart';
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

  /// Get auth scope from headers.
  String? getAuthScope(Map<String, String>? headers) {
    final authHeader =
        headers?['Authorization'] ?? headers?['authorization'];
    if (authHeader == null) return null;
    if (authHeader.startsWith('Bearer ')) return 'bearer';
    if (authHeader.startsWith('Basic ')) return 'basic';
    return 'auth';
  }

  /// Execute HTTP request with caching and coalescing.
  Future<void> executeRequest({
    required String method,
    required String url,
    required Map<String, dynamic>? queryParams,
    required Map<String, String>? headers,
    required Object? body,
    required CachePolicy cachePolicy,
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
      if (cachePolicy.shouldCheckCache) {
        final cached = await _checkCache(key, cachePolicy, decode);
        if (cached != null) {
          _emitCacheHit(key, cached, groups);

          if (cachePolicy == CachePolicy.staleWhileRevalidate) {
            _refreshInBackground(
              method: method,
              key: key,
              headers: headers,
              body: body,
              decode: decode,
              ttl: ttl,
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
      if (cachePolicy == CachePolicy.cacheOnly) {
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

      // Mark inflight
      _markInflight(key, scope, groups);

      // Execute with coalescing
      final response = await bloc.coalescer.coalesce(
        key,
        () => _executeNetwork(method, url, queryParams, headers, body, key),
      );

      // Cache response
      await _cacheResponse(
        key,
        response,
        cachePolicy,
        ttl,
        cacheAuthResponses,
        forceCache,
        url,
        headers,
      );

      // Handle success
      _handleSuccess(key, response, decode, startTime, groups);
    } catch (e, stackTrace) {
      // Try stale cache on error
      if (allowStaleOnError && cachePolicy != CachePolicy.networkOnly) {
        final stale = await bloc.cacheManager.getStale(key);
        if (stale != null) {
          final decoded = _decodeFromCache(stale, decode);
          _emitSuccess(key, decoded, groups);
          return;
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
      return _decodeFromCache(record, decode);
    }

    if (record.isExpired) return null;
    return _decodeFromCache(record, decode);
  }

  dynamic _decodeFromCache(
    WireCacheRecord record,
    dynamic Function(dynamic)? decode,
  ) {
    final jsonData = record.bodyJson;
    if (decode != null) return decode(jsonData);
    return jsonData;
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

  Future<Response<dynamic>> _executeNetwork(
    String method,
    String url,
    Map<String, dynamic>? queryParams,
    Map<String, String>? headers,
    Object? body,
    RequestKey key,
  ) {
    final status = bloc.state.activeRequests[key.canonical];

    return bloc.dio.request<dynamic>(
      url,
      data: body,
      queryParameters: queryParams,
      options: Options(method: method, headers: headers),
      cancelToken: status?.cancelToken,
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
    final decoded = _decodeResponse(response, decode);
    final elapsed = DateTime.now().difference(startTime);
    final bytesReceived = response.data?.toString().length ?? 0;

    _emitSuccess(key, decoded, groups, elapsed, bytesReceived);
  }

  dynamic _decodeResponse(
    Response<dynamic> response,
    dynamic Function(dynamic)? decode,
  ) {
    dynamic jsonData;
    if (response.data is String) {
      jsonData = jsonDecode(response.data as String);
    } else {
      jsonData = response.data;
    }

    if (decode != null) return decode(jsonData);
    return jsonData;
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
        .then((response) async {
          final record =
              WireCacheRecord.fromResponse(response, key.canonical, ttl: ttl);
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
