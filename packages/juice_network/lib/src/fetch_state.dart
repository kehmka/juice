import 'package:juice/juice.dart';

import 'fetch_config.dart';
import 'fetch_exceptions.dart';
import 'request/request_key.dart';
import 'request/request_status.dart';

/// Network statistics.
@immutable
class NetworkStats {
  /// Total requests made (success + failure).
  final int totalRequests;

  /// Successful requests.
  final int successCount;

  /// Failed requests.
  final int failureCount;

  /// Cache hits.
  final int cacheHits;

  /// Cache misses.
  final int cacheMisses;

  /// Total bytes received.
  final int bytesReceived;

  /// Total bytes sent.
  final int bytesSent;

  /// Total response time in milliseconds (for averaging).
  /// This is the sum of all successful response times.
  final double _totalResponseTimeMs;

  /// Number of retries performed.
  final int retryCount;

  /// Number of requests coalesced (deduplicated).
  final int coalescedCount;

  const NetworkStats({
    this.totalRequests = 0,
    this.successCount = 0,
    this.failureCount = 0,
    this.cacheHits = 0,
    this.cacheMisses = 0,
    this.bytesReceived = 0,
    this.bytesSent = 0,
    double totalResponseTimeMs = 0,
    this.retryCount = 0,
    this.coalescedCount = 0,
  }) : _totalResponseTimeMs = totalResponseTimeMs;

  /// Average response time in milliseconds (successful requests only).
  double get avgResponseTimeMs {
    if (successCount == 0) return 0;
    return _totalResponseTimeMs / successCount;
  }

  /// Hit rate as a percentage.
  double get hitRate {
    final total = cacheHits + cacheMisses;
    if (total == 0) return 0;
    return cacheHits / total * 100;
  }

  /// Success rate as a percentage.
  double get successRate {
    if (totalRequests == 0) return 0;
    return successCount / totalRequests * 100;
  }

  /// Record a successful request.
  NetworkStats withSuccess(int bytesReceived, Duration responseTime) {
    return NetworkStats(
      totalRequests: totalRequests + 1,
      successCount: successCount + 1,
      failureCount: failureCount,
      cacheHits: cacheHits,
      cacheMisses: cacheMisses,
      bytesReceived: this.bytesReceived + bytesReceived,
      bytesSent: bytesSent,
      totalResponseTimeMs: _totalResponseTimeMs + responseTime.inMilliseconds,
      retryCount: retryCount,
      coalescedCount: coalescedCount,
    );
  }

  /// Record a failed request.
  NetworkStats withFailure() {
    return NetworkStats(
      totalRequests: totalRequests + 1,
      successCount: successCount,
      failureCount: failureCount + 1,
      cacheHits: cacheHits,
      cacheMisses: cacheMisses,
      bytesReceived: bytesReceived,
      bytesSent: bytesSent,
      totalResponseTimeMs: _totalResponseTimeMs,
      retryCount: retryCount,
      coalescedCount: coalescedCount,
    );
  }

  /// Record bytes sent.
  NetworkStats withBytesSent(int bytes) {
    return NetworkStats(
      totalRequests: totalRequests,
      successCount: successCount,
      failureCount: failureCount,
      cacheHits: cacheHits,
      cacheMisses: cacheMisses,
      bytesReceived: bytesReceived,
      bytesSent: bytesSent + bytes,
      totalResponseTimeMs: _totalResponseTimeMs,
      retryCount: retryCount,
      coalescedCount: coalescedCount,
    );
  }

  /// Record a cache hit.
  NetworkStats withCacheHit() {
    return NetworkStats(
      totalRequests: totalRequests,
      successCount: successCount,
      failureCount: failureCount,
      cacheHits: cacheHits + 1,
      cacheMisses: cacheMisses,
      bytesReceived: bytesReceived,
      bytesSent: bytesSent,
      totalResponseTimeMs: _totalResponseTimeMs,
      retryCount: retryCount,
      coalescedCount: coalescedCount,
    );
  }

  /// Record a cache miss.
  NetworkStats withCacheMiss() {
    return NetworkStats(
      totalRequests: totalRequests,
      successCount: successCount,
      failureCount: failureCount,
      cacheHits: cacheHits,
      cacheMisses: cacheMisses + 1,
      bytesReceived: bytesReceived,
      bytesSent: bytesSent,
      totalResponseTimeMs: _totalResponseTimeMs,
      retryCount: retryCount,
      coalescedCount: coalescedCount,
    );
  }

  /// Record a retry.
  NetworkStats withRetry() {
    return NetworkStats(
      totalRequests: totalRequests,
      successCount: successCount,
      failureCount: failureCount,
      cacheHits: cacheHits,
      cacheMisses: cacheMisses,
      bytesReceived: bytesReceived,
      bytesSent: bytesSent,
      totalResponseTimeMs: _totalResponseTimeMs,
      retryCount: retryCount + 1,
      coalescedCount: coalescedCount,
    );
  }

  /// Record a coalesced request.
  NetworkStats withCoalesced() {
    return NetworkStats(
      totalRequests: totalRequests,
      successCount: successCount,
      failureCount: failureCount,
      cacheHits: cacheHits,
      cacheMisses: cacheMisses,
      bytesReceived: bytesReceived,
      bytesSent: bytesSent,
      totalResponseTimeMs: _totalResponseTimeMs,
      retryCount: retryCount,
      coalescedCount: coalescedCount + 1,
    );
  }

  /// Reset all statistics.
  factory NetworkStats.zero() => const NetworkStats();
}

/// Cache statistics.
@immutable
class CacheStats {
  /// Number of entries in cache.
  final int entryCount;

  /// Total size of cache in bytes.
  final int totalBytes;

  /// Number of expired entries.
  final int expiredCount;

  const CacheStats({
    this.entryCount = 0,
    this.totalBytes = 0,
    this.expiredCount = 0,
  });

  static const CacheStats zero = CacheStats();
}

/// State for FetchBloc.
@immutable
class FetchState extends BlocState {
  /// Whether FetchBloc has been initialized.
  final bool isInitialized;

  /// Current configuration.
  final FetchConfig config;

  /// Active requests by canonical key.
  final Map<String, RequestStatus> activeRequests;

  /// Count of inflight requests.
  final int inflightCount;

  /// Network statistics.
  final NetworkStats stats;

  /// Cache statistics.
  final CacheStats cacheStats;

  /// Last error that occurred.
  final FetchError? lastError;

  const FetchState({
    this.isInitialized = false,
    this.config = const FetchConfig(),
    this.activeRequests = const {},
    this.inflightCount = 0,
    this.stats = const NetworkStats(),
    this.cacheStats = const CacheStats(),
    this.lastError,
  });

  /// Initial state.
  factory FetchState.initial() => const FetchState();

  /// Check if a request is active.
  bool isActive(RequestKey key) => activeRequests.containsKey(key.canonical);

  /// Check if a request is inflight.
  bool isInflight(RequestKey key) {
    final status = activeRequests[key.canonical];
    return status?.phase == RequestPhase.inflight;
  }

  /// Get status for a request.
  RequestStatus? getStatus(RequestKey key) => activeRequests[key.canonical];

  /// Whether any requests are inflight.
  bool get hasInflight => inflightCount > 0;

  /// Whether an error occurred recently.
  bool get hasError => lastError != null;

  /// Creates a copy of this state with the given fields replaced.
  FetchState copyWith({
    bool? isInitialized,
    FetchConfig? config,
    Map<String, RequestStatus>? activeRequests,
    int? inflightCount,
    NetworkStats? stats,
    CacheStats? cacheStats,
    FetchError? lastError,
    bool clearLastError = false,
  }) {
    return FetchState(
      isInitialized: isInitialized ?? this.isInitialized,
      config: config ?? this.config,
      activeRequests: activeRequests ?? this.activeRequests,
      inflightCount: inflightCount ?? this.inflightCount,
      stats: stats ?? this.stats,
      cacheStats: cacheStats ?? this.cacheStats,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
    );
  }
}

/// Rebuild groups for FetchBloc.
abstract class FetchGroups {
  /// Configuration changes.
  static const config = 'fetch:config';

  /// Inflight count changes.
  static const inflight = 'fetch:inflight';

  /// Cache statistics changes.
  static const cache = 'fetch:cache';

  /// Statistics changes.
  static const statsGroup = 'fetch:stats';

  /// Error changes.
  static const error = 'fetch:error';

  /// Specific request by canonical key.
  static String request(String canonical) => 'fetch:request:$canonical';

  /// Requests matching URL pattern.
  static String url(String pattern) => 'fetch:url:$pattern';
}
