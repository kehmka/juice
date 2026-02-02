import 'package:juice/juice.dart';

import 'cache/cache_index.dart';
import 'core/bloc_result_ops.dart';
import 'storage_config.dart';
import 'storage_events.dart';
import 'storage_state.dart';
import 'use_cases/use_cases.dart';

/// BLoC for managing local storage operations.
///
/// Provides a unified API for multiple storage backends:
/// - **Hive** - structured local key-value with boxes
/// - **SharedPreferences** - simple key-value storage
/// - **SQLite** - relational database storage
/// - **Secure Storage** - encrypted storage for secrets
///
/// All operations flow through events and use cases. Helper methods are thin
/// wrappers around `sendAndWaitResult()` for convenience.
///
/// ## Example
///
/// ```dart
/// // Setup
/// final storage = StorageBloc(config: StorageConfig(
///   hiveBoxesToOpen: ['cache', 'settings'],
///   prefsKeyPrefix: 'myapp_',
/// ));
///
/// // Initialize first
/// await storage.initialize();
///
/// // Using helper methods (recommended)
/// final theme = await storage.prefsRead<String>('theme');
/// await storage.prefsWrite('theme', 'dark');
///
/// // With TTL (auto-expires after 1 hour)
/// await storage.hiveWrite('cache', 'user_data', userData, ttl: Duration(hours: 1));
///
/// // Secure storage for secrets
/// await storage.secureWrite('auth_token', token);
/// final token = await storage.secureRead('auth_token');
/// ```
class StorageBloc extends JuiceBloc<StorageState> {
  final StorageConfig _config;
  final CacheIndex _cacheIndex;
  Timer? _cleanupTimer;
  bool _cleanupRunning = false;

  /// For testing: allows overriding the current time.
  ///
  /// Setting this propagates to the underlying [CacheIndex], so TTL
  /// expiration checks use the same clock.
  @visibleForTesting
  DateTime Function() get clock => _cacheIndex.clock;
  set clock(DateTime Function() value) => _cacheIndex.clock = value;

  /// Creates a StorageBloc with the given configuration.
  ///
  /// Optionally accepts a [cacheIndex] for testing.
  factory StorageBloc({required StorageConfig config, CacheIndex? cacheIndex}) {
    final index = cacheIndex ?? CacheIndex();
    return StorageBloc._(config: config, cacheIndex: index);
  }

  StorageBloc._({required StorageConfig config, required CacheIndex cacheIndex})
      : _config = config,
        _cacheIndex = cacheIndex,
        super(
          const StorageState(),
          _buildUseCases(config, cacheIndex),
        );

  static List<UseCaseBuilderGenerator> _buildUseCases(
    StorageConfig config,
    CacheIndex cacheIndex,
  ) {
    return [
      // Initialize
      () => UseCaseBuilder(
            typeOfEvent: InitializeStorageEvent,
            useCaseGenerator: () =>
                InitializeUseCase(config: config, cacheIndex: cacheIndex),
          ),

      // Hive
      () => UseCaseBuilder(
            typeOfEvent: HiveOpenBoxEvent,
            useCaseGenerator: () => HiveOpenBoxUseCase(),
          ),
      () => UseCaseBuilder(
            typeOfEvent: HiveCloseBoxEvent,
            useCaseGenerator: () => HiveCloseBoxUseCase(),
          ),
      () => UseCaseBuilder(
            typeOfEvent: HiveReadEvent,
            useCaseGenerator: () => HiveReadUseCase(cacheIndex: cacheIndex),
          ),
      () => UseCaseBuilder(
            typeOfEvent: HiveWriteEvent,
            useCaseGenerator: () => HiveWriteUseCase(cacheIndex: cacheIndex),
          ),
      () => UseCaseBuilder(
            typeOfEvent: HiveDeleteEvent,
            useCaseGenerator: () => HiveDeleteUseCase(cacheIndex: cacheIndex),
          ),

      // Prefs
      () => UseCaseBuilder(
            typeOfEvent: PrefsReadEvent,
            useCaseGenerator: () => PrefsReadUseCase(cacheIndex: cacheIndex),
          ),
      () => UseCaseBuilder(
            typeOfEvent: PrefsWriteEvent,
            useCaseGenerator: () => PrefsWriteUseCase(cacheIndex: cacheIndex),
          ),
      () => UseCaseBuilder(
            typeOfEvent: PrefsDeleteEvent,
            useCaseGenerator: () => PrefsDeleteUseCase(cacheIndex: cacheIndex),
          ),

      // Secure
      () => UseCaseBuilder(
            typeOfEvent: SecureReadEvent,
            useCaseGenerator: () => SecureReadUseCase(),
          ),
      () => UseCaseBuilder(
            typeOfEvent: SecureWriteEvent,
            useCaseGenerator: () => SecureWriteUseCase(),
          ),
      () => UseCaseBuilder(
            typeOfEvent: SecureDeleteEvent,
            useCaseGenerator: () => SecureDeleteUseCase(),
          ),
      () => UseCaseBuilder(
            typeOfEvent: SecureDeleteAllEvent,
            useCaseGenerator: () => SecureDeleteAllUseCase(),
          ),

      // SQLite
      () => UseCaseBuilder(
            typeOfEvent: SqliteQueryEvent,
            useCaseGenerator: () => SqliteQueryUseCase(),
          ),
      () => UseCaseBuilder(
            typeOfEvent: SqliteInsertEvent,
            useCaseGenerator: () => SqliteInsertUseCase(),
          ),
      () => UseCaseBuilder(
            typeOfEvent: SqliteUpdateEvent,
            useCaseGenerator: () => SqliteUpdateUseCase(),
          ),
      () => UseCaseBuilder(
            typeOfEvent: SqliteDeleteEvent,
            useCaseGenerator: () => SqliteDeleteUseCase(),
          ),
      () => UseCaseBuilder(
            typeOfEvent: SqliteRawEvent,
            useCaseGenerator: () => SqliteRawUseCase(),
          ),

      // Cache management
      () => UseCaseBuilder(
            typeOfEvent: CacheCleanupEvent,
            useCaseGenerator: () => CacheCleanupUseCase(cacheIndex: cacheIndex),
          ),
      () => UseCaseBuilder(
            typeOfEvent: ClearAllEvent,
            useCaseGenerator: () => ClearAllUseCase(cacheIndex: cacheIndex),
          ),
    ];
  }

  /// The storage configuration.
  StorageConfig get config => _config;

  /// The cache index for TTL metadata.
  CacheIndex get cacheIndex => _cacheIndex;

  // ===========================================================================
  // Rebuild Groups
  // ===========================================================================

  /// Rebuild group for initialization status.
  static const String groupInit = 'storage:init';

  /// Rebuild group for SharedPreferences changes.
  static const String groupPrefs = 'storage:prefs';

  /// Rebuild group for secure storage changes.
  static const String groupSecure = 'storage:secure';

  /// Rebuild group for cache metadata changes.
  static const String groupCache = 'storage:cache';

  /// Get rebuild group for a specific Hive box.
  static String groupHive(String boxName) => 'storage:hive:$boxName';

  /// Get rebuild group for a specific SQLite table.
  static String groupSqlite(String tableName) => 'storage:sqlite:$tableName';

  // ===========================================================================
  // Initialization
  // ===========================================================================

  /// Initialize all storage backends.
  ///
  /// This must be called before using any storage operations.
  /// Optionally starts background cleanup if enabled in config.
  Future<void> initialize() async {
    await sendForResult<void>(InitializeStorageEvent(
      groupsToRebuild: {groupInit},
    ));

    // Start background cleanup if enabled
    if (_config.enableBackgroundCleanup) {
      _startBackgroundCleanup();
    }
  }

  void _startBackgroundCleanup() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(
      _config.cacheCleanupInterval,
      (_) async {
        if (_cleanupRunning) return;
        _cleanupRunning = true;
        try {
          await cleanupExpiredCache();
        } catch (_) {
          // Background cleanup is best-effort; errors are surfaced
          // through state.cacheStats / emitFailure inside the use case.
        } finally {
          _cleanupRunning = false;
        }
      },
    );
  }

  // ===========================================================================
  // Hive Helpers
  // ===========================================================================

  /// Read a value from Hive.
  ///
  /// Returns null if the key doesn't exist or has expired (TTL).
  Future<T?> hiveRead<T>(String box, String key) async {
    final value =
        await sendForResult<Object?>(HiveReadEvent(box: box, key: key));
    return value as T?;
  }

  /// Write a value to Hive with optional TTL.
  ///
  /// If [ttl] is provided, the entry will automatically expire after the duration.
  Future<void> hiveWrite<T>(
    String box,
    String key,
    T value, {
    Duration? ttl,
  }) async {
    await sendForResult<void>(HiveWriteEvent(
      box: box,
      key: key,
      value: value,
      ttl: ttl,
    ));
  }

  /// Delete a value from Hive.
  Future<void> hiveDelete(String box, String key) async {
    await sendForResult<void>(HiveDeleteEvent(box: box, key: key));
  }

  /// Open a Hive box.
  Future<void> hiveOpenBox(String box, {bool lazy = false}) async {
    await sendForResult<void>(HiveOpenBoxEvent(box: box, lazy: lazy));
  }

  /// Close a Hive box.
  Future<void> hiveCloseBox(String box) async {
    await sendForResult<void>(HiveCloseBoxEvent(box: box));
  }

  // ===========================================================================
  // SharedPreferences Helpers
  // ===========================================================================

  /// Read a value from SharedPreferences.
  ///
  /// Returns null if the key doesn't exist or has expired (TTL).
  Future<T?> prefsRead<T>(String key) async {
    final value = await sendForResult<Object?>(PrefsReadEvent(key: key));
    return value as T?;
  }

  /// Write a value to SharedPreferences with optional TTL.
  Future<void> prefsWrite<T>(String key, T value, {Duration? ttl}) async {
    await sendForResult<void>(
        PrefsWriteEvent(key: key, value: value, ttl: ttl));
  }

  /// Delete a value from SharedPreferences.
  Future<void> prefsDelete(String key) async {
    await sendForResult<void>(PrefsDeleteEvent(key: key));
  }

  // ===========================================================================
  // Secure Storage Helpers
  // ===========================================================================

  /// Read a value from secure storage.
  ///
  /// Returns null if the key doesn't exist.
  Future<String?> secureRead(String key) async {
    final value = await sendForResult<Object?>(SecureReadEvent(key: key));
    return value as String?;
  }

  /// Write a value to secure storage.
  ///
  /// Note: TTL is not supported for secure storage. Secrets require explicit deletion.
  Future<void> secureWrite(String key, String value) async {
    await sendForResult<void>(SecureWriteEvent(key: key, value: value));
  }

  /// Delete a value from secure storage.
  Future<void> secureDelete(String key) async {
    await sendForResult<void>(SecureDeleteEvent(key: key));
  }

  /// Delete all secure storage.
  Future<void> secureClearAll() async {
    await sendForResult<void>(SecureDeleteAllEvent());
  }

  // ===========================================================================
  // SQLite Helpers
  // ===========================================================================

  /// Execute a SQLite query.
  Future<List<Map<String, dynamic>>> sqliteQuery(
    String sql, [
    List<dynamic>? arguments,
  ]) async {
    final value = await sendForResult<Object?>(
      SqliteQueryEvent(sql: sql, arguments: arguments),
    );
    return value as List<Map<String, dynamic>>;
  }

  /// Insert a row into SQLite.
  ///
  /// Returns the row ID of the inserted row.
  Future<int> sqliteInsert(String table, Map<String, dynamic> values) async {
    final value = await sendForResult<Object?>(
      SqliteInsertEvent(table: table, values: values),
    );
    return value as int;
  }

  /// Update rows in SQLite.
  ///
  /// Returns the number of rows affected.
  Future<int> sqliteUpdate(
    String table,
    Map<String, dynamic> values, {
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    final value = await sendForResult<Object?>(SqliteUpdateEvent(
      table: table,
      values: values,
      where: where,
      whereArgs: whereArgs,
    ));
    return value as int;
  }

  /// Delete rows from SQLite.
  ///
  /// Returns the number of rows deleted.
  Future<int> sqliteDelete(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    final value = await sendForResult<Object?>(SqliteDeleteEvent(
      table: table,
      where: where,
      whereArgs: whereArgs,
    ));
    return value as int;
  }

  /// Execute raw SQL.
  Future<void> sqliteRaw(String sql, [List<dynamic>? arguments]) async {
    await sendForResult<void>(SqliteRawEvent(sql: sql, arguments: arguments));
  }

  // ===========================================================================
  // Cache Management Helpers
  // ===========================================================================

  /// Run cache cleanup immediately.
  ///
  /// Returns the number of entries cleaned.
  Future<int> cleanupExpiredCache() async {
    final value = await sendForResult<Object?>(CacheCleanupEvent(runNow: true));
    return value as int? ?? 0;
  }

  /// Clear all storage (logout scenario).
  Future<void> clearAll(
      [ClearAllOptions options = const ClearAllOptions()]) async {
    await sendForResult<void>(ClearAllEvent(options: options));
  }

  @override
  Future<void> close() async {
    _cleanupTimer?.cancel();
    await _cacheIndex.close();
    await super.close();
  }
}
