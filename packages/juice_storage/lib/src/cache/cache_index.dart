import 'package:hive/hive.dart';
import 'package:juice/juice.dart' show visibleForTesting;
import '../core/storage_keys.dart';
import 'cache_metadata.dart';

/// Index for managing cache TTL metadata.
///
/// Uses a dedicated Hive box to track expiration times for cached entries
/// across all storage backends that support TTL.
class CacheIndex {
  static const String _boxName = '_juice_cache_metadata';

  late Box<CacheMetadata> _metadataBox;
  bool _initialized = false;

  /// For testing: allows overriding the current time.
  @visibleForTesting
  DateTime Function() clock = () => DateTime.now();

  /// Whether the cache index has been initialized.
  bool get isInitialized => _initialized;

  /// Initialize the cache index.
  Future<void> init() async {
    if (_initialized) return;
    ensureAdapterRegistered();
    _metadataBox = await Hive.openBox<CacheMetadata>(_boxName);
    _initialized = true;
  }

  /// Ensures the CacheMetadata adapter is registered.
  static void ensureAdapterRegistered() {
    const typeId = 200;
    if (!Hive.isAdapterRegistered(typeId)) {
      Hive.registerAdapter(CacheMetadataAdapter());
    }
  }

  /// Close the cache index.
  Future<void> close() async {
    if (!_initialized) return;
    await _metadataBox.close();
    _initialized = false;
  }

  /// Generate a canonical storage key for TTL-enabled backends.
  ///
  /// Delegates to [StorageKeys] for consistent key format across the library.
  /// Only 'hive' and 'prefs' backends support TTL.
  ///
  /// Format: "hive:{box}:{key}" for Hive, "prefs:{key}" for SharedPreferences.
  String canonicalKey(String backend, String key, [String? box]) {
    switch (backend) {
      case 'hive':
        if (box == null) {
          throw ArgumentError('Box name required for Hive keys');
        }
        return StorageKeys.hive(box, key);
      case 'prefs':
        return StorageKeys.prefs(key);
      default:
        throw ArgumentError('TTL not supported for backend: $backend');
    }
  }

  /// Set expiration for a storage key.
  Future<void> setExpiry(String storageKey, Duration ttl) async {
    _ensureInitialized();
    await _metadataBox.put(
      storageKey,
      CacheMetadata.withTTL(
        storageKey: storageKey,
        ttl: ttl,
        now: clock(),
      ),
    );
  }

  /// Check if a storage key has expired.
  ///
  /// Returns false if no TTL is set (never expires).
  bool isExpired(String storageKey) {
    _ensureInitialized();
    final meta = _metadataBox.get(storageKey);
    if (meta == null) return false; // No TTL = never expires
    return clock().isAfter(meta.expiresAt);
  }

  /// Get metadata for a storage key.
  CacheMetadata? getMetadata(String storageKey) {
    _ensureInitialized();
    return _metadataBox.get(storageKey);
  }

  /// Remove expiration metadata for a storage key.
  Future<void> removeExpiry(String storageKey) async {
    _ensureInitialized();
    await _metadataBox.delete(storageKey);
  }

  /// Get all expired entries.
  List<CacheMetadata> getExpiredEntries() {
    _ensureInitialized();
    final now = clock();
    return _metadataBox.values
        .where((m) => now.isAfter(m.expiresAt))
        .toList();
  }

  /// Get count of all metadata entries.
  int get metadataCount {
    _ensureInitialized();
    return _metadataBox.length;
  }

  /// Get count of expired entries.
  int get expiredCount {
    _ensureInitialized();
    final now = clock();
    return _metadataBox.values.where((m) => now.isAfter(m.expiresAt)).length;
  }

  /// Clear all metadata.
  Future<void> clear() async {
    _ensureInitialized();
    await _metadataBox.clear();
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('CacheIndex not initialized. Call init() first.');
    }
  }
}
