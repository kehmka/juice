/// Backend types supported by the demo.
enum DemoBackend { prefs, hive, secure, sqlite }

/// A demo entry representing a stored value.
///
/// Tracks metadata for UI display including TTL countdown.
class DemoEntry {
  DemoEntry({
    required this.backend,
    required this.key,
    required this.value,
    required this.createdAt,
    this.ttl,
  }) : id = '${backend.name}:${DateTime.now().microsecondsSinceEpoch}:$key';

  /// Unique ID for AnimatedList tracking.
  final String id;

  /// Which storage backend this entry uses.
  final DemoBackend backend;

  /// The storage key.
  final String key;

  /// The stored value (as string for display).
  final String value;

  /// When this entry was created.
  final DateTime createdAt;

  /// Time-to-live duration (null = no expiry).
  final Duration? ttl;

  /// When this entry expires (null if no TTL).
  DateTime? get expiresAt => ttl == null ? null : createdAt.add(ttl!);

  /// Whether this entry has expired based on [now].
  bool isExpired(DateTime now) {
    final exp = expiresAt;
    if (exp == null) return false;
    return now.isAfter(exp);
  }

  /// Seconds remaining until expiry (0 if expired or no TTL).
  int secondsRemaining(DateTime now) {
    final exp = expiresAt;
    if (exp == null) return 0;
    final diff = exp.difference(now).inSeconds;
    return diff < 0 ? 0 : diff;
  }

  /// Progress from 0.0 (expired) to 1.0 (just created) for TTL countdown.
  double? progress(DateTime now) {
    if (ttl == null) return null;
    final total = ttl!.inSeconds;
    if (total == 0) return 0.0;
    final remaining = secondsRemaining(now);
    return remaining / total;
  }
}
