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

  /// Maximum memory cache size as percentage of maxCacheSize.
  /// Memory cache is a hot cache subset of the total.
  static const double _memoryCacheRatio = 0.2; // 20% of max

  /// In-memory cache for frequently accessed entries.
  /// Uses LinkedHashMap for LRU ordering (insertion order).
  final Map<String, WireCacheRecord> _memoryCache = {};

  /// Tracked disk cache size in bytes (estimate).
  /// Updated on put/delete operations.
  int _trackedDiskSize = 0;

  /// Map of canonical key to size for disk entries we've written.
  /// Used for accurate size tracking on delete.
  final Map<String, int> _diskEntrySizes = {};

  /// Maximum entries in memory cache (fallback limit).
  static const int _maxMemoryCacheEntries = 100;

  CacheManager({
    required this.storageBloc,
    this.maxCacheSize = 50 * 1024 * 1024, // 50 MB
  });

  /// Maximum memory cache size in bytes.
  int get _maxMemoryCacheSize => (maxCacheSize * _memoryCacheRatio).toInt();

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
    final recordSize = record.sizeBytes;

    // Add to memory cache
    _addToMemoryCache(canonical, record);

    // Track disk size: subtract old entry size if replacing
    final oldSize = _diskEntrySizes[canonical] ?? 0;
    _trackedDiskSize = _trackedDiskSize - oldSize + recordSize;
    _diskEntrySizes[canonical] = recordSize;

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

    // Update tracked disk size
    final entrySize = _diskEntrySizes.remove(canonical) ?? 0;
    _trackedDiskSize = (_trackedDiskSize - entrySize).clamp(0, maxCacheSize * 2);

    await storageBloc.hiveDelete(cacheBoxName, canonical);
  }

  /// Delete entries matching a URL pattern.
  ///
  /// Scans both memory cache and disk storage for matching keys.
  Future<int> deletePattern(String urlPattern) async {
    final regex = RegExp(urlPattern);
    final toRemove = <String>{};

    // Collect matching keys from memory cache
    for (final key in _memoryCache.keys) {
      if (regex.hasMatch(key)) {
        toRemove.add(key);
      }
    }

    // Scan disk keys for additional matches
    final diskKeys = await storageBloc.hiveKeys(cacheBoxName);
    for (final key in diskKeys) {
      if (regex.hasMatch(key)) {
        toRemove.add(key);
      }
    }

    // Delete all matching entries
    for (final key in toRemove) {
      _memoryCache.remove(key);
      final entrySize = _diskEntrySizes.remove(key) ?? 0;
      _trackedDiskSize = (_trackedDiskSize - entrySize).clamp(0, maxCacheSize * 2);
      await storageBloc.hiveDelete(cacheBoxName, key);
    }

    return toRemove.length;
  }

  /// Delete entries matching a namespace prefix.
  ///
  /// Namespace is typically the first segment of the canonical key (e.g., "user:123:GET:/api").
  Future<int> deleteNamespace(String namespace) async {
    final prefix = '$namespace:';
    final toRemove = <String>{};

    // Collect matching keys from memory cache
    for (final key in _memoryCache.keys) {
      if (key.startsWith(prefix)) {
        toRemove.add(key);
      }
    }

    // Scan disk keys for additional matches
    final diskKeys = await storageBloc.hiveKeys(cacheBoxName);
    for (final key in diskKeys) {
      if (key.startsWith(prefix)) {
        toRemove.add(key);
      }
    }

    // Delete all matching entries
    for (final key in toRemove) {
      _memoryCache.remove(key);
      final entrySize = _diskEntrySizes.remove(key) ?? 0;
      _trackedDiskSize = (_trackedDiskSize - entrySize).clamp(0, maxCacheSize * 2);
      await storageBloc.hiveDelete(cacheBoxName, key);
    }

    return toRemove.length;
  }

  /// Get all cache keys (memory + disk).
  Future<List<String>> getAllKeys() async {
    final allKeys = <String>{..._memoryCache.keys};
    final diskKeys = await storageBloc.hiveKeys(cacheBoxName);
    allKeys.addAll(diskKeys);
    return allKeys.toList();
  }

  /// Delete entries matching a URL pattern with expiry filtering.
  ///
  /// If [includeExpired] is false, only non-expired entries are deleted.
  Future<int> deletePatternFiltered(
    String urlPattern, {
    bool includeExpired = true,
  }) async {
    final regex = RegExp(urlPattern);
    final allKeys = await getAllKeys();
    var deleted = 0;

    for (final key in allKeys) {
      if (!regex.hasMatch(key)) continue;

      // Check expiry if filtering
      if (!includeExpired) {
        final record = _memoryCache[key];
        if (record != null && record.isExpired) continue;

        // For disk-only entries, load to check expiry
        if (record == null) {
          final bytes =
              await storageBloc.hiveRead<Uint8List>(cacheBoxName, key);
          if (bytes != null) {
            try {
              final diskRecord = WireCacheRecord.fromBytes(bytes);
              if (diskRecord.isExpired) continue;
            } catch (_) {
              // Corrupted entry - delete it anyway
            }
          }
        }
      }

      // Delete the entry
      _memoryCache.remove(key);
      final entrySize = _diskEntrySizes.remove(key) ?? 0;
      _trackedDiskSize = (_trackedDiskSize - entrySize).clamp(0, maxCacheSize * 2);
      await storageBloc.hiveDelete(cacheBoxName, key);
      deleted++;
    }

    return deleted;
  }

  /// Delete entries matching a namespace prefix with expiry filtering.
  Future<int> deleteNamespaceFiltered(
    String namespace, {
    bool includeExpired = true,
  }) async {
    final prefix = '$namespace:';
    final allKeys = await getAllKeys();
    var deleted = 0;

    for (final key in allKeys) {
      if (!key.startsWith(prefix)) continue;

      // Check expiry if filtering
      if (!includeExpired) {
        final record = _memoryCache[key];
        if (record != null && record.isExpired) continue;

        // For disk-only entries, load to check expiry
        if (record == null) {
          final bytes =
              await storageBloc.hiveRead<Uint8List>(cacheBoxName, key);
          if (bytes != null) {
            try {
              final diskRecord = WireCacheRecord.fromBytes(bytes);
              if (diskRecord.isExpired) continue;
            } catch (_) {
              // Corrupted entry - delete it anyway
            }
          }
        }
      }

      // Delete the entry
      _memoryCache.remove(key);
      final entrySize = _diskEntrySizes.remove(key) ?? 0;
      _trackedDiskSize = (_trackedDiskSize - entrySize).clamp(0, maxCacheSize * 2);
      await storageBloc.hiveDelete(cacheBoxName, key);
      deleted++;
    }

    return deleted;
  }

  /// Clear all cache entries.
  Future<void> clear() async {
    _memoryCache.clear();
    _diskEntrySizes.clear();
    _trackedDiskSize = 0;

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
  /// If [namespace] is provided, only cleans up expired entries in that namespace.
  /// Returns the total number of entries cleaned (memory + disk).
  Future<int> cleanupExpired({String? namespace}) async {
    final prefix = namespace != null ? '$namespace:' : null;
    var cleaned = 0;

    // Remove expired from memory cache
    final expiredMemory = _memoryCache.entries
        .where((e) {
          if (!e.value.isExpired) return false;
          if (prefix != null && !e.key.startsWith(prefix)) return false;
          return true;
        })
        .map((e) => e.key)
        .toList();

    for (final key in expiredMemory) {
      _memoryCache.remove(key);
      cleaned++;
    }

    if (namespace != null) {
      // For namespaced cleanup, scan disk keys manually
      final diskKeys = await storageBloc.hiveKeys(cacheBoxName);
      for (final key in diskKeys) {
        if (!key.startsWith(prefix!)) continue;

        // Check if expired
        final bytes = await storageBloc.hiveRead<Uint8List>(cacheBoxName, key);
        if (bytes == null) continue;

        try {
          final record = WireCacheRecord.fromBytes(bytes);
          if (record.isExpired) {
            final entrySize = _diskEntrySizes.remove(key) ?? 0;
            _trackedDiskSize =
                (_trackedDiskSize - entrySize).clamp(0, maxCacheSize * 2);
            await storageBloc.hiveDelete(cacheBoxName, key);
            cleaned++;
          }
        } catch (_) {
          // Corrupted entry - delete it
          await storageBloc.hiveDelete(cacheBoxName, key);
          cleaned++;
        }
      }
    } else {
      // StorageBloc handles TTL eviction for full cleanup
      final diskCleanedRaw = await storageBloc
          .sendForResult<Object?>(CacheCleanupEvent(runNow: true));
      final diskCleaned = diskCleanedRaw as int? ?? 0;
      cleaned += diskCleaned;
    }

    return cleaned;
  }

  /// Evict entries if over size limit using LRU.
  Future<void> _evictIfNeeded() async {
    // 1. Enforce memory cache size limit (by bytes, not just count)
    await _evictMemoryCacheIfNeeded();

    // 2. Enforce total disk cache size limit
    await _evictDiskCacheIfNeeded();
  }

  /// Evict from memory cache if over size limit.
  Future<void> _evictMemoryCacheIfNeeded() async {
    // Check both size and count limits
    while (memoryCacheSize > _maxMemoryCacheSize ||
        _memoryCache.length > _maxMemoryCacheEntries) {
      if (_memoryCache.isEmpty) break;

      // Remove oldest entry (first inserted - LRU approximation)
      final oldestKey = _memoryCache.keys.first;
      _memoryCache.remove(oldestKey);
    }
  }

  /// Evict from disk cache if over size limit.
  Future<void> _evictDiskCacheIfNeeded() async {
    if (_trackedDiskSize <= maxCacheSize) return;

    // Target 90% of max to avoid thrashing
    final targetSize = (maxCacheSize * 0.9).toInt();

    // Sort entries by size (evict largest first for faster reduction)
    // Alternative: could use insertion order for true LRU
    final sortedEntries = _diskEntrySizes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    for (final entry in sortedEntries) {
      if (_trackedDiskSize <= targetSize) break;

      final key = entry.key;
      final size = entry.value;

      // Remove from memory cache too
      _memoryCache.remove(key);

      // Remove from disk
      _diskEntrySizes.remove(key);
      _trackedDiskSize = (_trackedDiskSize - size).clamp(0, maxCacheSize * 2);

      await storageBloc.hiveDelete(cacheBoxName, key);
    }
  }

  /// Add to memory cache with size limiting.
  void _addToMemoryCache(String key, WireCacheRecord record) {
    // Remove existing entry first (for accurate size tracking)
    _memoryCache.remove(key);

    // Add new entry
    _memoryCache[key] = record;

    // Evict if over limits (sync eviction for memory cache)
    while (memoryCacheSize > _maxMemoryCacheSize ||
        _memoryCache.length > _maxMemoryCacheEntries) {
      if (_memoryCache.isEmpty || _memoryCache.length <= 1) break;

      // Remove oldest entry (first key in LinkedHashMap = LRU)
      final oldest = _memoryCache.keys.first;
      if (oldest == key) break; // Don't evict the entry we just added
      _memoryCache.remove(oldest);
    }
  }

  /// Get memory cache size in bytes.
  int get memoryCacheSize =>
      _memoryCache.values.fold(0, (sum, r) => sum + r.sizeBytes);

  /// Get memory cache entry count.
  int get memoryCacheCount => _memoryCache.length;

  /// Get tracked disk cache size in bytes (estimate).
  int get diskCacheSize => _trackedDiskSize;

  /// Get disk cache entry count (tracked entries only).
  int get diskCacheCount => _diskEntrySizes.length;

  /// Get total cache size (memory + disk) in bytes.
  int get totalCacheSize => memoryCacheSize + _trackedDiskSize;

  /// Get maximum cache size in bytes.
  int get maxSize => maxCacheSize;

  /// Check if cache is over the size limit.
  bool get isOverLimit => _trackedDiskSize > maxCacheSize;
}
