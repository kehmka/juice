/// Canonical storage key builder for TTL metadata and debugging.
///
/// All storage keys follow a deterministic scheme:
/// - Hive: `hive:{box}:{key}`
/// - SharedPreferences: `prefs:{key}`
/// - Secure Storage: `secure:{key}`
/// - SQLite: `sqlite:{table}:{primaryKey}`
class StorageKeys {
  StorageKeys._();

  /// Build a canonical key for SharedPreferences.
  static String prefs(String key) => 'prefs:$key';

  /// Build a canonical key for Hive.
  static String hive(String box, String key) => 'hive:$box:$key';

  /// Build a canonical key for Secure Storage.
  static String secure(String key) => 'secure:$key';

  /// Build a canonical key for SQLite.
  static String sqlite(String table, String pk) => 'sqlite:$table:$pk';

  /// Parse a canonical key to extract its components.
  ///
  /// Returns a record with (backend, parts) where:
  /// - backend is 'hive', 'prefs', 'secure', or 'sqlite'
  /// - parts is a list of the remaining components
  static ({String backend, List<String> parts}) parse(String storageKey) {
    final colonIndex = storageKey.indexOf(':');
    if (colonIndex == -1) {
      throw ArgumentError('Invalid storage key format: $storageKey');
    }

    final backend = storageKey.substring(0, colonIndex);
    final remainder = storageKey.substring(colonIndex + 1);

    switch (backend) {
      case 'hive':
        // hive:box:key
        final secondColon = remainder.indexOf(':');
        if (secondColon == -1) {
          throw ArgumentError('Invalid Hive storage key: $storageKey');
        }
        return (
          backend: backend,
          parts: [
            remainder.substring(0, secondColon),
            remainder.substring(secondColon + 1),
          ],
        );
      case 'prefs':
      case 'secure':
        // prefs:key or secure:key
        return (backend: backend, parts: [remainder]);
      case 'sqlite':
        // sqlite:table:pk
        final secondColon = remainder.indexOf(':');
        if (secondColon == -1) {
          throw ArgumentError('Invalid SQLite storage key: $storageKey');
        }
        return (
          backend: backend,
          parts: [
            remainder.substring(0, secondColon),
            remainder.substring(secondColon + 1),
          ],
        );
      default:
        throw ArgumentError('Unknown backend in storage key: $storageKey');
    }
  }
}
