import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:sqflite/sqflite.dart';

/// Configuration for the StorageBloc.
///
/// Controls behavior for all storage backends including Hive, SharedPreferences,
/// SQLite, and Secure Storage.
class StorageConfig {
  /// Path for Hive storage. If null, uses default path.
  final String? hivePath;

  /// Hive boxes to automatically open on initialization.
  final List<String> hiveBoxesToOpen;

  /// Hive type adapters to register.
  final List<TypeAdapter<dynamic>> hiveAdapters;

  /// Prefix for SharedPreferences keys.
  ///
  /// All keys will be prefixed with this value to namespace Juice storage
  /// and avoid conflicts with other preferences.
  /// Example: "juice_" -> keys become "juice_theme", "juice_locale"
  final String prefsKeyPrefix;

  /// SQLite database name.
  final String sqliteDatabaseName;

  /// SQLite database version for migrations.
  final int sqliteDatabaseVersion;

  /// Callback for SQLite database creation.
  final OnDatabaseCreateFn? sqliteOnCreate;

  /// Callback for SQLite database upgrades.
  final OnDatabaseVersionChangeFn? sqliteOnUpgrade;

  /// iOS-specific options for secure storage.
  final IOSOptions? secureStorageIOS;

  /// Android-specific options for secure storage.
  final AndroidOptions? secureStorageAndroid;

  /// Interval for background cache cleanup.
  final Duration cacheCleanupInterval;

  /// Whether to enable periodic background cache cleanup.
  final bool enableBackgroundCleanup;

  const StorageConfig({
    this.hivePath,
    this.hiveBoxesToOpen = const [],
    this.hiveAdapters = const [],
    this.prefsKeyPrefix = 'juice_',
    this.sqliteDatabaseName = 'juice.db',
    this.sqliteDatabaseVersion = 1,
    this.sqliteOnCreate,
    this.sqliteOnUpgrade,
    this.secureStorageIOS,
    this.secureStorageAndroid,
    this.cacheCleanupInterval = const Duration(minutes: 15),
    this.enableBackgroundCleanup = true,
  });

  /// Creates a minimal config for testing.
  factory StorageConfig.test() => const StorageConfig(
        enableBackgroundCleanup: false,
      );
}
