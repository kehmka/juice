/// Cache policy determining how requests interact with the cache.
enum CachePolicy {
  /// Always fetch from network, never use cache.
  /// Use for real-time data that must be fresh.
  networkOnly,

  /// Only return cached data, never fetch from network.
  /// Use for offline-first scenarios or known-stale-ok data.
  cacheOnly,

  /// Return cache if valid, otherwise fetch from network.
  /// Use for data that doesn't change often.
  cacheFirst,

  /// Always fetch from network, fall back to cache on failure.
  /// Default policy - balances freshness with resilience.
  networkFirst,

  /// Return stale cache immediately, refresh in background.
  /// Use for perceived performance with eventual consistency.
  staleWhileRevalidate,
}

/// Extension methods for CachePolicy.
extension CachePolicyExtension on CachePolicy {
  /// Whether this policy should check cache before network.
  bool get shouldCheckCache => switch (this) {
        CachePolicy.networkOnly => false,
        CachePolicy.cacheOnly => true,
        CachePolicy.cacheFirst => true,
        CachePolicy.networkFirst => false,
        CachePolicy.staleWhileRevalidate => true,
      };

  /// Whether this policy should store responses in cache.
  bool get shouldCache => switch (this) {
        CachePolicy.networkOnly => false,
        CachePolicy.cacheOnly => false, // Already in cache
        CachePolicy.cacheFirst => true,
        CachePolicy.networkFirst => true,
        CachePolicy.staleWhileRevalidate => true,
      };

  /// Whether this policy should fetch from network.
  bool get shouldFetch => switch (this) {
        CachePolicy.networkOnly => true,
        CachePolicy.cacheOnly => false,
        CachePolicy.cacheFirst => true, // On cache miss
        CachePolicy.networkFirst => true,
        CachePolicy.staleWhileRevalidate => true,
      };

  /// Whether this policy allows stale data on error.
  bool get allowsStaleOnError => switch (this) {
        CachePolicy.networkOnly => false,
        CachePolicy.cacheOnly => false,
        CachePolicy.cacheFirst => false,
        CachePolicy.networkFirst => true,
        CachePolicy.staleWhileRevalidate => true,
      };
}
