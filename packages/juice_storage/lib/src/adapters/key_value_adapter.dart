/// Abstract interface for key-value storage adapters.
///
/// Used by Hive, SharedPreferences, and Secure Storage backends.
/// SQLite uses [SqliteGateway] instead (query-based, not key-value).
///
/// **Note:** Adapters are internal implementation details. Public consumers
/// should use StorageBloc helpers or events.
abstract class KeyValueAdapter<T> {
  /// Read a value by key.
  ///
  /// Returns null if the key doesn't exist.
  Future<T?> read(String key);

  /// Write a value with the given key.
  Future<void> write(String key, T value);

  /// Delete a value by key.
  Future<void> delete(String key);

  /// Clear all values.
  Future<void> clear();

  /// Check if a key exists.
  Future<bool> containsKey(String key);

  /// Get all keys.
  Future<Iterable<String>> keys();
}
