import 'package:juice/juice.dart';

import 'cache/cache_policy.dart';
import 'fetch_config.dart';
import 'interceptors/interceptor.dart';
import 'request/request_key.dart';

// =============================================================================
// Lifecycle Events
// =============================================================================

/// Initialize the FetchBloc with configuration.
class InitializeFetchEvent extends EventBase {
  final FetchConfig config;
  final List<FetchInterceptor>? interceptors;

  InitializeFetchEvent({
    this.config = const FetchConfig(),
    this.interceptors,
  });
}

/// Reset FetchBloc to baseline state.
class ResetFetchEvent extends EventBase {
  final bool clearCache;
  final bool cancelInflight;
  final bool resetStats;

  ResetFetchEvent({
    this.clearCache = false,
    this.cancelInflight = true,
    this.resetStats = true,
  });
}

/// Reconfigure interceptors on an already-initialized FetchBloc.
class ReconfigureInterceptorsEvent extends EventBase {
  final List<FetchInterceptor> interceptors;

  ReconfigureInterceptorsEvent({
    required this.interceptors,
  });
}

// =============================================================================
// Request Events
// =============================================================================

/// GET request.
class GetEvent extends EventBase {
  final String url;
  final Map<String, dynamic>? queryParams;
  final Map<String, String>? headers;

  /// Cache policy. If null, uses [FetchConfig.defaultCachePolicy].
  final CachePolicy? cachePolicy;

  /// TTL for cached response. If null, uses [FetchConfig.defaultTtl].
  final Duration? ttl;
  final bool cacheAuthResponses;
  final bool forceCache;
  final bool allowStaleOnError;
  final bool retryable;

  /// Max retry attempts. If null, uses [FetchConfig.defaultMaxRetries].
  final int? maxAttempts;
  final dynamic Function(dynamic raw)? decode;
  final String? scope;
  final String? variant;
  final RequestKey? keyOverride;

  GetEvent({
    required this.url,
    this.queryParams,
    this.headers,
    this.cachePolicy, // null = use config default
    this.ttl, // null = use config default
    this.cacheAuthResponses = false,
    this.forceCache = false,
    this.allowStaleOnError = true,
    this.retryable = true,
    this.maxAttempts, // null = use config default
    this.decode,
    this.scope,
    this.variant,
    this.keyOverride,
    super.groupsToRebuild,
  });
}

/// POST request.
class PostEvent extends EventBase {
  final String url;
  final Object? body;
  final Map<String, dynamic>? queryParams;
  final Map<String, String>? headers;

  /// Cache policy. If null, uses [CachePolicy.networkOnly] for POST.
  final CachePolicy? cachePolicy;

  /// TTL for cached response. If null, uses [FetchConfig.defaultTtl].
  final Duration? ttl;
  final bool cacheAuthResponses;
  final bool forceCache;
  final bool allowStaleOnError;
  final bool retryable;

  /// Max retry attempts. If null, uses [FetchConfig.defaultMaxRetries].
  final int? maxAttempts;
  final String? idempotencyKey;
  final dynamic Function(dynamic raw)? decode;
  final String? scope;
  final String? variant;
  final RequestKey? keyOverride;

  PostEvent({
    required this.url,
    this.body,
    this.queryParams,
    this.headers,
    this.cachePolicy, // null = networkOnly for POST (mutations shouldn't cache by default)
    this.ttl,
    this.cacheAuthResponses = false,
    this.forceCache = false,
    this.allowStaleOnError = false,
    this.retryable = false,
    this.maxAttempts,
    this.idempotencyKey,
    this.decode,
    this.scope,
    this.variant,
    this.keyOverride,
    super.groupsToRebuild,
  });
}

/// PUT request.
class PutEvent extends EventBase {
  final String url;
  final Object? body;
  final Map<String, dynamic>? queryParams;
  final Map<String, String>? headers;

  /// Cache policy. If null, uses [CachePolicy.networkOnly] for PUT.
  final CachePolicy? cachePolicy;
  final Duration? ttl;
  final bool cacheAuthResponses;
  final bool forceCache;
  final bool allowStaleOnError;
  final bool retryable;

  /// Max retry attempts. If null, uses [FetchConfig.defaultMaxRetries].
  final int? maxAttempts;
  final String? idempotencyKey;
  final dynamic Function(dynamic raw)? decode;
  final String? scope;
  final String? variant;
  final RequestKey? keyOverride;

  PutEvent({
    required this.url,
    this.body,
    this.queryParams,
    this.headers,
    this.cachePolicy, // null = networkOnly for PUT
    this.ttl,
    this.cacheAuthResponses = false,
    this.forceCache = false,
    this.allowStaleOnError = false,
    this.retryable = true,
    this.maxAttempts,
    this.idempotencyKey,
    this.decode,
    this.scope,
    this.variant,
    this.keyOverride,
    super.groupsToRebuild,
  });
}

/// PATCH request.
class PatchEvent extends EventBase {
  final String url;
  final Object? body;
  final Map<String, dynamic>? queryParams;
  final Map<String, String>? headers;

  /// Cache policy. If null, uses [CachePolicy.networkOnly] for PATCH.
  final CachePolicy? cachePolicy;
  final Duration? ttl;
  final bool cacheAuthResponses;
  final bool forceCache;
  final bool allowStaleOnError;
  final bool retryable;

  /// Max retry attempts. If null, uses [FetchConfig.defaultMaxRetries].
  final int? maxAttempts;
  final String? idempotencyKey;
  final dynamic Function(dynamic raw)? decode;
  final String? scope;
  final String? variant;
  final RequestKey? keyOverride;

  PatchEvent({
    required this.url,
    this.body,
    this.queryParams,
    this.headers,
    this.cachePolicy, // null = networkOnly for PATCH
    this.ttl,
    this.cacheAuthResponses = false,
    this.forceCache = false,
    this.allowStaleOnError = false,
    this.retryable = false,
    this.maxAttempts,
    this.idempotencyKey,
    this.decode,
    this.scope,
    this.variant,
    this.keyOverride,
    super.groupsToRebuild,
  });
}

/// DELETE request.
class DeleteEvent extends EventBase {
  final String url;
  final Map<String, dynamic>? queryParams;
  final Map<String, String>? headers;

  /// Cache policy. If null, uses [CachePolicy.networkOnly] for DELETE.
  final CachePolicy? cachePolicy;
  final bool retryable;

  /// Max retry attempts. If null, uses [FetchConfig.defaultMaxRetries].
  final int? maxAttempts;
  final dynamic Function(dynamic raw)? decode;
  final String? scope;
  final String? variant;
  final RequestKey? keyOverride;

  DeleteEvent({
    required this.url,
    this.queryParams,
    this.headers,
    this.cachePolicy, // null = networkOnly for DELETE
    this.retryable = true,
    this.maxAttempts,
    this.decode,
    this.scope,
    this.variant,
    this.keyOverride,
    super.groupsToRebuild,
  });
}

/// HEAD request.
class HeadEvent extends EventBase {
  final String url;
  final Map<String, dynamic>? queryParams;
  final Map<String, String>? headers;
  final bool retryable;
  final String? scope;

  HeadEvent({
    required this.url,
    this.queryParams,
    this.headers,
    this.retryable = true,
    this.scope,
    super.groupsToRebuild,
  });
}

// =============================================================================
// Cache Events
// =============================================================================

/// Invalidate cache entries.
class InvalidateCacheEvent extends EventBase {
  final RequestKey? key;
  final String? urlPattern;
  final String? namespace;
  final bool includeExpired;

  InvalidateCacheEvent({
    this.key,
    this.urlPattern,
    this.namespace,
    this.includeExpired = true,
  });
}

/// Clear all cached responses.
class ClearCacheEvent extends EventBase {
  final String? namespace;

  ClearCacheEvent({this.namespace});
}

/// Prune cache to target size.
class PruneCacheEvent extends EventBase {
  final int? targetBytes;
  final bool removeExpiredFirst;

  PruneCacheEvent({
    this.targetBytes,
    this.removeExpiredFirst = true,
  });
}

/// Clean up expired cache entries.
class CleanupExpiredCacheEvent extends EventBase {
  final String? namespace;

  CleanupExpiredCacheEvent({this.namespace});
}

// =============================================================================
// Cancellation Events
// =============================================================================

/// Cancel a specific request.
class CancelRequestEvent extends EventBase {
  final RequestKey key;
  final String? reason;

  CancelRequestEvent({
    required this.key,
    this.reason,
  });
}

/// Cancel all requests in a scope.
class CancelScopeEvent extends EventBase {
  final String scope;
  final String? reason;

  CancelScopeEvent({
    required this.scope,
    this.reason,
  });
}

/// Cancel all inflight requests.
class CancelAllEvent extends EventBase {
  final String? reason;

  CancelAllEvent({this.reason});
}

// =============================================================================
// Observability Events
// =============================================================================

/// Reset network statistics.
class ResetStatsEvent extends EventBase {}

/// Clear the last error.
class ClearLastErrorEvent extends EventBase {}
