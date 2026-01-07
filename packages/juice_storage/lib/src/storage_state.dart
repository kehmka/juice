import 'package:juice/juice.dart';
import 'cache/cache_stats.dart';

/// State of a storage backend.
enum BackendState {
  uninitialized,
  initializing,
  ready,
  error,
}

/// Status of all storage backends.
class StorageBackendStatus {
  final BackendState hive;
  final BackendState prefs;
  final BackendState sqlite;
  final BackendState secure;

  const StorageBackendStatus({
    this.hive = BackendState.uninitialized,
    this.prefs = BackendState.uninitialized,
    this.sqlite = BackendState.uninitialized,
    this.secure = BackendState.uninitialized,
  });

  StorageBackendStatus copyWith({
    BackendState? hive,
    BackendState? prefs,
    BackendState? sqlite,
    BackendState? secure,
  }) {
    return StorageBackendStatus(
      hive: hive ?? this.hive,
      prefs: prefs ?? this.prefs,
      sqlite: sqlite ?? this.sqlite,
      secure: secure ?? this.secure,
    );
  }

  bool get allReady =>
      hive == BackendState.ready &&
      prefs == BackendState.ready &&
      sqlite == BackendState.ready &&
      secure == BackendState.ready;
}

/// Information about an open Hive box.
class BoxInfo {
  final String name;
  final bool isLazy;
  final int entryCount;

  const BoxInfo({
    required this.name,
    this.isLazy = false,
    this.entryCount = 0,
  });
}

/// Information about a SQLite table.
class TableInfo {
  final String name;
  final int rowCount;

  const TableInfo({
    required this.name,
    this.rowCount = 0,
  });
}

/// Error information stored in state.
class StorageError {
  final String message;
  final StorageErrorType type;
  final String? storageKey;
  final String? requestId;
  final DateTime timestamp;

  const StorageError({
    required this.message,
    required this.type,
    this.storageKey,
    this.requestId,
    required this.timestamp,
  });
}

/// Error types for storage operations.
enum StorageErrorType {
  notInitialized,
  backendNotAvailable,
  boxNotOpen,
  keyNotFound,
  typeError,
  serializationError,
  encryptionError,
  platformNotSupported,
  sqliteError,
  permissionDenied,
}

/// State for the StorageBloc.
///
/// NOTE: Read results are NOT stored in state. They are returned via
/// [OperationResult] to prevent concurrency bugs. State only contains:
/// - Initialization/health information
/// - Backend availability
/// - Cache statistics
/// - Last error (for debugging)
class StorageState extends BlocState {
  /// Whether the storage system is initialized.
  final bool isInitialized;

  /// Status of each storage backend.
  final StorageBackendStatus backendStatus;

  /// Information about open Hive boxes.
  final Map<String, BoxInfo> hiveBoxes;

  /// Information about SQLite tables.
  final Map<String, TableInfo> sqliteTables;

  /// Whether secure storage is available on this platform.
  final bool secureStorageAvailable;

  /// The last error that occurred.
  final StorageError? lastError;

  /// Cache statistics.
  final CacheStats cacheStats;

  const StorageState({
    this.isInitialized = false,
    this.backendStatus = const StorageBackendStatus(),
    this.hiveBoxes = const {},
    this.sqliteTables = const {},
    this.secureStorageAvailable = false,
    this.lastError,
    this.cacheStats = const CacheStats(),
  });

  /// Creates a copy of this state with the given fields replaced.
  StorageState copyWith({
    bool? isInitialized,
    StorageBackendStatus? backendStatus,
    Map<String, BoxInfo>? hiveBoxes,
    Map<String, TableInfo>? sqliteTables,
    bool? secureStorageAvailable,
    StorageError? lastError,
    CacheStats? cacheStats,
    bool clearLastError = false,
  }) {
    return StorageState(
      isInitialized: isInitialized ?? this.isInitialized,
      backendStatus: backendStatus ?? this.backendStatus,
      hiveBoxes: hiveBoxes ?? this.hiveBoxes,
      sqliteTables: sqliteTables ?? this.sqliteTables,
      secureStorageAvailable:
          secureStorageAvailable ?? this.secureStorageAvailable,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      cacheStats: cacheStats ?? this.cacheStats,
    );
  }
}
