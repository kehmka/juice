/// Local storage, caching, and secure storage for the Juice framework.
///
/// Provides a unified BLoC-based API for multiple storage backends:
/// - **Hive** - structured local key-value with boxes
/// - **SharedPreferences** - simple key-value storage
/// - **SQLite** - relational database storage
/// - **Secure Storage** - encrypted storage for secrets
///
/// ## Quick Start
///
/// ```dart
/// // Create the bloc with configuration
/// final storage = StorageBloc(config: StorageConfig(
///   hiveBoxesToOpen: ['cache', 'settings'],
///   prefsKeyPrefix: 'myapp_',
/// ));
///
/// // Use helper methods
/// await storage.prefsWrite('theme', 'dark');
/// final theme = await storage.prefsRead<String>('theme');
///
/// // With TTL
/// await storage.hiveWrite('cache', 'data', myData, ttl: Duration(hours: 1));
///
/// // Secure storage for secrets
/// await storage.secureWrite('token', authToken);
/// ```
///
/// ## Rebuild Groups
///
/// - `storage:init` - Initialization status
/// - `storage:hive:{boxName}` - Per-box changes
/// - `storage:prefs` - SharedPreferences changes
/// - `storage:sqlite:{tableName}` - Per-table changes
/// - `storage:secure` - Secure storage changes
/// - `storage:cache` - Cache metadata changes
library juice_storage;

// Core
export 'src/storage_bloc.dart';
export 'src/storage_state.dart';
export 'src/storage_events.dart';
export 'src/storage_config.dart';
export 'src/storage_exceptions.dart';

// Result types (for advanced usage)
export 'src/core/result_event.dart';
export 'src/core/operation_result.dart';
export 'src/core/bloc_result_ops.dart';
export 'src/core/storage_keys.dart';

// Cache
export 'src/cache/cache_metadata.dart';
export 'src/cache/cache_stats.dart';
export 'src/cache/cache_index.dart';

// NOTE: Adapters are NOT exported. They are internal implementation details.
// Tests should use MockStorageBloc or in-memory adapters via @visibleForTesting.
