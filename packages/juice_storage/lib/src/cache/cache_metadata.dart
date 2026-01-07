import 'package:hive/hive.dart';

part 'cache_metadata.g.dart';

/// Metadata for cached items with TTL support.
///
/// Stored in a dedicated Hive box "_juice_cache_metadata".
///
/// **INVARIANT:** juice_storage reserves Hive typeIds 200-223.
/// CacheMetadata uses 200 to avoid collisions in mono-repos.
@HiveType(typeId: 200)
class CacheMetadata {
  /// Canonical storage key (e.g., "hive:cache:user_123", "prefs:theme_mode").
  @HiveField(0)
  final String storageKey;

  /// When this cache entry expires.
  @HiveField(1)
  final DateTime expiresAt;

  /// When this cache entry was created.
  @HiveField(2)
  final DateTime createdAt;

  CacheMetadata({
    required this.storageKey,
    required this.expiresAt,
    required this.createdAt,
  });

  /// Whether this cache entry has expired.
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Time remaining until expiration.
  Duration get timeRemaining => expiresAt.difference(DateTime.now());

  /// Creates metadata for a new cache entry with the given TTL.
  factory CacheMetadata.withTTL({
    required String storageKey,
    required Duration ttl,
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();
    return CacheMetadata(
      storageKey: storageKey,
      createdAt: timestamp,
      expiresAt: timestamp.add(ttl),
    );
  }
}
