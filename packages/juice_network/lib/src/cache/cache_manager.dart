import 'dart:typed_data';

import 'package:juice_storage/juice_storage.dart';

import '../request/request_key.dart';
import 'wire_cache_record.dart';

/// Manages HTTP response cache using StorageBloc for persistence.
///
/// The cache stores raw wire responses (bytes) to avoid decoder issues
/// and type fragmentation.
class CacheManager {
  /// StorageBloc for persistence.
  final StorageBloc storageBloc;

  /// Hive box name for cache entries.
  ///
  /// Users should include this in [StorageConfig.hiveBoxesToOpen] when
  /// configuring StorageBloc for use with FetchBloc:
  ///
  /// ```dart
  /// StorageConfig(
  ///   hiveBoxesToOpen: [CacheManager.cacheBoxName, ...otherBoxes],
  /// )
  /// ```
  static const String cacheBoxName = 'fetch_cache';

  /// Maximum cache size in bytes.
  final int maxCacheSize;

  /// In-memory cache for frequently accessed entries.
  final Map<String, WireCacheRecord> _memoryCache = {};

  /// Maximum entries in memory cache.
  static const int _maxMemoryCacheEntries = 100;

  CacheManager({
    required this.storageBloc,
    this.maxCacheSize = 50 * 1024 * 1024, // 50 MB
  });

  /// Initialize the cache (open Hive box).
  Future<void> initialize() async {
    await storageBloc.hiveOpenBox(cacheBoxName);
  }

  /// Get a cached response.
  Future<WireCacheRecord?> get(RequestKey key) async {
    final canonical = key.canonical;

    // Check memory cache first
    final memoryHit = _memoryCache[canonical];
    if (memoryHit != null) {
      // Check if expired and should be removed
      if (memoryHit.isExpired) {
        _memoryCache.remove(canonical);
        // Don't remove from disk yet - stale-while-revalidate may use it
      } else {
        return memoryHit;
      }
    }

    // Check disk cache
    final bytes = await storageBloc.hiveRead<Uint8List>(cacheBoxName, canonical);
    if (bytes == null) return null;

    try {
      final record = WireCacheRecord.fromBytes(bytes);

      // Add to memory cache if not expired
      if (!record.isExpired) {
        _addToMemoryCache(canonical, record);
      }

      return record;
    } catch (e) {
      // Corrupted cache entry - remove it
      await delete(key);
      return null;
    }
  }

  /// Get a cached response, including expired (stale) entries.
  Future<WireCacheRecord?> getStale(RequestKey key) async {
    final canonical = key.canonical;

    // Check memory cache first (even stale)
    final memoryHit = _memoryCache[canonical];
    if (memoryHit != null) return memoryHit;

    // Check disk cache
    final bytes = await storageBloc.hiveRead<Uint8List>(cacheBoxName, canonical);
    if (bytes == null) return null;

    try {
      return WireCacheRecord.fromBytes(bytes);
    } catch (e) {
      await delete(key);
      return null;
    }
  }

  /// Store a response in cache.
  Future<void> put(RequestKey key, WireCacheRecord record) async {
    final canonical = key.canonical;

    // Add to memory cache
    _addToMemoryCache(canonical, record);

    // Store to disk with TTL
    final ttl = record.expiresAt?.difference(DateTime.now());

    await storageBloc.hiveWrite(
      cacheBoxName,
      canonical,
      record.toBytes(),
      ttl: ttl,
    );

    // Evict if over size limit
    await _evictIfNeeded();
  }

  /// Delete a cache entry.
  Future<void> delete(RequestKey key) async {
    final canonical = key.canonical;
    _memoryCache.remove(canonical);
    await storageBloc.hiveDelete(cacheBoxName, canonical);
  }

  /// Delete entries matching a URL pattern.
  Future<int> deletePattern(String urlPattern) async {
    // This is a simplistic implementation - a production version
    // would need to scan keys in the Hive box
    final regex = RegExp(urlPattern);
    final toRemove = _memoryCache.keys
        .where((key) => regex.hasMatch(key))
        .toList();

    for (final key in toRemove) {
      _memoryCache.remove(key);
      await storageBloc.hiveDelete(cacheBoxName, key);
    }

    return toRemove.length;
  }

  /// Clear all cache entries.
  Future<void> clear() async {
    _memoryCache.clear();
    // Clear all entries in the cache box using sendForResult to await completion
    await storageBloc.sendForResult<void>(ClearAllEvent(
      options: ClearAllOptions(
        clearHive: true,
        clearPrefs: false,
        clearSecure: false,
        clearSqlite: false,
        hiveBoxesToClear: [cacheBoxName],
      ),
    ));
  }

  /// Clean up expired entries.
  ///
  /// Returns the total number of entries cleaned (memory + disk).
  Future<int> cleanupExpired() async {
    // Remove expired from memory cache
    final expiredMemory = _memoryCache.entries
        .where((e) => e.value.isExpired)
        .map((e) => e.key)
        .toList();

    for (final key in expiredMemory) {
      _memoryCache.remove(key);
    }

    // StorageBloc handles TTL eviction - await completion and get count
    final diskCleanedRaw = await storageBloc
        .sendForResult<Object?>(CacheCleanupEvent(runNow: true));
    final diskCleaned = diskCleanedRaw as int? ?? 0;

    return expiredMemory.length + diskCleaned;
  }

  /// Evict entries if over size limit using LRU.
  Future<void> _evictIfNeeded() async {
    // For now, just limit memory cache size
    // Full LRU eviction would require tracking access times in storage
    if (_memoryCache.length > _maxMemoryCacheEntries) {
      // Remove oldest entries (first inserted)
      final toRemove = _memoryCache.length - _maxMemoryCacheEntries;
      final keys = _memoryCache.keys.take(toRemove).toList();
      for (final key in keys) {
        _memoryCache.remove(key);
      }
    }

    // Disk eviction is handled by StorageBloc's cache cleanup
  }

  /// Add to memory cache with size limiting.
  void _addToMemoryCache(String key, WireCacheRecord record) {
    _memoryCache[key] = record;

    // Limit memory cache size
    if (_memoryCache.length > _maxMemoryCacheEntries) {
      final oldest = _memoryCache.keys.first;
      _memoryCache.remove(oldest);
    }
  }

  /// Get approximate cache size (memory cache only).
  int get memoryCacheSize =>
      _memoryCache.values.fold(0, (sum, r) => sum + r.sizeBytes);

  /// Get memory cache entry count.
  int get memoryCacheCount => _memoryCache.length;
}
