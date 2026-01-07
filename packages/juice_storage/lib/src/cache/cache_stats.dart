/// Statistics about the cache system.
class CacheStats {
  /// Total number of entries with TTL metadata.
  final int metadataCount;

  /// Number of currently expired entries.
  final int expiredCount;

  /// When the last cleanup ran.
  final DateTime? lastCleanupAt;

  /// How many entries were cleaned in the last cleanup.
  final int lastCleanupCleanedCount;

  const CacheStats({
    this.metadataCount = 0,
    this.expiredCount = 0,
    this.lastCleanupAt,
    this.lastCleanupCleanedCount = 0,
  });

  CacheStats copyWith({
    int? metadataCount,
    int? expiredCount,
    DateTime? lastCleanupAt,
    int? lastCleanupCleanedCount,
  }) {
    return CacheStats(
      metadataCount: metadataCount ?? this.metadataCount,
      expiredCount: expiredCount ?? this.expiredCount,
      lastCleanupAt: lastCleanupAt ?? this.lastCleanupAt,
      lastCleanupCleanedCount:
          lastCleanupCleanedCount ?? this.lastCleanupCleanedCount,
    );
  }
}
