import 'core/result_event.dart';

// =============================================================================
// Initialization Events
// =============================================================================

/// Initialize the storage system.
///
/// Returns void on completion.
class InitializeStorageEvent extends StorageResultEvent<void> {
  InitializeStorageEvent({
    super.requestId,
    super.groupsToRebuild,
  });
}

// =============================================================================
// Hive Events
// =============================================================================

/// Open a Hive box.
///
/// Returns void on completion.
class HiveOpenBoxEvent extends StorageResultEvent<void> {
  final String box;
  final bool lazy;

  HiveOpenBoxEvent({
    required this.box,
    this.lazy = false,
    super.requestId,
    super.groupsToRebuild,
  });
}

/// Read a value from Hive.
///
/// Returns Object? (the stored value, or null if not found/expired).
/// NOTE: Events are non-generic. Helpers provide the generic cast.
class HiveReadEvent extends StorageResultEvent<Object?> {
  final String box;
  final String key;

  HiveReadEvent({
    required this.box,
    required this.key,
    super.requestId,
    super.groupsToRebuild,
  });
}

/// Write a value to Hive.
///
/// Returns void on completion.
class HiveWriteEvent extends StorageResultEvent<void> {
  final String box;
  final String key;
  final Object? value;
  final Duration? ttl;

  HiveWriteEvent({
    required this.box,
    required this.key,
    required this.value,
    this.ttl,
    super.requestId,
    super.groupsToRebuild,
  });
}

/// Delete a value from Hive.
///
/// Returns void on completion.
class HiveDeleteEvent extends StorageResultEvent<void> {
  final String box;
  final String key;

  HiveDeleteEvent({
    required this.box,
    required this.key,
    super.requestId,
    super.groupsToRebuild,
  });
}

/// Close a Hive box.
///
/// Returns void on completion.
class HiveCloseBoxEvent extends StorageResultEvent<void> {
  final String box;

  HiveCloseBoxEvent({
    required this.box,
    super.requestId,
    super.groupsToRebuild,
  });
}

// =============================================================================
// SharedPreferences Events
// =============================================================================

/// Read a value from SharedPreferences.
///
/// Returns Object? (the stored value, or null if not found/expired).
/// NOTE: Events are non-generic. Helpers provide the generic cast.
class PrefsReadEvent extends StorageResultEvent<Object?> {
  final String key;

  PrefsReadEvent({
    required this.key,
    super.requestId,
    super.groupsToRebuild,
  });
}

/// Write a value to SharedPreferences.
///
/// Returns void on completion.
class PrefsWriteEvent extends StorageResultEvent<void> {
  final String key;
  final Object? value;
  final Duration? ttl;

  PrefsWriteEvent({
    required this.key,
    required this.value,
    this.ttl,
    super.requestId,
    super.groupsToRebuild,
  });
}

/// Delete a value from SharedPreferences.
///
/// Returns void on completion.
class PrefsDeleteEvent extends StorageResultEvent<void> {
  final String key;

  PrefsDeleteEvent({
    required this.key,
    super.requestId,
    super.groupsToRebuild,
  });
}

// =============================================================================
// SQLite Events
// =============================================================================

/// Execute a SQLite query.
///
/// Returns Object? (List<Map<String, dynamic>>).
class SqliteQueryEvent extends StorageResultEvent<Object?> {
  final String sql;
  final List<dynamic>? arguments;

  SqliteQueryEvent({
    required this.sql,
    this.arguments,
    super.requestId,
    super.groupsToRebuild,
  });
}

/// Insert a row into SQLite.
///
/// Returns Object? (int row id).
class SqliteInsertEvent extends StorageResultEvent<Object?> {
  final String table;
  final Map<String, dynamic> values;

  SqliteInsertEvent({
    required this.table,
    required this.values,
    super.requestId,
    super.groupsToRebuild,
  });
}

/// Update rows in SQLite.
///
/// Returns Object? (int rows affected).
class SqliteUpdateEvent extends StorageResultEvent<Object?> {
  final String table;
  final Map<String, dynamic> values;
  final String? where;
  final List<dynamic>? whereArgs;

  SqliteUpdateEvent({
    required this.table,
    required this.values,
    this.where,
    this.whereArgs,
    super.requestId,
    super.groupsToRebuild,
  });
}

/// Delete rows from SQLite.
///
/// Returns Object? (int rows deleted).
class SqliteDeleteEvent extends StorageResultEvent<Object?> {
  final String table;
  final String? where;
  final List<dynamic>? whereArgs;

  SqliteDeleteEvent({
    required this.table,
    this.where,
    this.whereArgs,
    super.requestId,
    super.groupsToRebuild,
  });
}

/// Execute raw SQL.
///
/// Returns void on completion.
class SqliteRawEvent extends StorageResultEvent<void> {
  final String sql;
  final List<dynamic>? arguments;

  SqliteRawEvent({
    required this.sql,
    this.arguments,
    super.requestId,
    super.groupsToRebuild,
  });
}

// =============================================================================
// Secure Storage Events
// =============================================================================

/// Read a value from secure storage.
///
/// Returns Object? (String value, or null if not found).
class SecureReadEvent extends StorageResultEvent<Object?> {
  final String key;

  SecureReadEvent({
    required this.key,
    super.requestId,
    super.groupsToRebuild,
  });
}

/// Write a value to secure storage.
///
/// Note: TTL is not supported for secure storage. Secrets require explicit deletion.
/// Returns void on completion.
class SecureWriteEvent extends StorageResultEvent<void> {
  final String key;
  final String value;

  SecureWriteEvent({
    required this.key,
    required this.value,
    super.requestId,
    super.groupsToRebuild,
  });
}

/// Delete a value from secure storage.
///
/// Returns void on completion.
class SecureDeleteEvent extends StorageResultEvent<void> {
  final String key;

  SecureDeleteEvent({
    required this.key,
    super.requestId,
    super.groupsToRebuild,
  });
}

/// Delete all secure storage.
///
/// Returns void on completion.
class SecureDeleteAllEvent extends StorageResultEvent<void> {
  SecureDeleteAllEvent({
    super.requestId,
    super.groupsToRebuild,
  });
}

// =============================================================================
// Cache Management Events
// =============================================================================

/// Clean up expired cache entries.
///
/// Returns Object? (int entries cleaned).
class CacheCleanupEvent extends StorageResultEvent<Object?> {
  /// If true, run cleanup immediately.
  final bool runNow;

  /// Interval for periodic cleanup setup.
  final Duration? interval;

  CacheCleanupEvent({
    this.runNow = false,
    this.interval,
    super.requestId,
    super.groupsToRebuild,
  });
}

/// Clear all storage (logout scenario).
///
/// Returns void on completion.
class ClearAllEvent extends StorageResultEvent<void> {
  final ClearAllOptions options;

  ClearAllEvent({
    this.options = const ClearAllOptions(),
    super.requestId,
    super.groupsToRebuild,
  });
}

/// Options for ClearAllEvent.
class ClearAllOptions {
  /// Whether to clear Hive storage.
  final bool clearHive;

  /// Whether to clear SharedPreferences.
  final bool clearPrefs;

  /// Whether to clear secure storage.
  final bool clearSecure;

  /// Whether to clear SQLite.
  final bool clearSqlite;

  /// Specific Hive boxes to clear. If null, clears all known boxes.
  final List<String>? hiveBoxesToClear;

  /// If true, drops SQLite tables. If false, only deletes rows.
  final bool sqliteDropTables;

  const ClearAllOptions({
    this.clearHive = true,
    this.clearPrefs = true,
    this.clearSecure = true,
    this.clearSqlite = true,
    this.hiveBoxesToClear,
    this.sqliteDropTables = false,
  });
}
