import 'package:hive_flutter/hive_flutter.dart';
import 'package:juice/juice.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../adapters/adapters.dart';
import '../cache/cache_index.dart';
import '../storage_bloc.dart';
import '../storage_config.dart';
import '../storage_events.dart';
import '../storage_exceptions.dart';
import '../storage_state.dart';

/// Use case for initializing all storage backends.
class InitializeUseCase
    extends BlocUseCase<StorageBloc, InitializeStorageEvent> {
  final StorageConfig config;
  final CacheIndex cacheIndex;

  InitializeUseCase({required this.config, required this.cacheIndex});

  @override
  Future<void> execute(InitializeStorageEvent event) async {
    try {
      var status = const StorageBackendStatus();

      // 1. Initialize Hive
      try {
        status = status.copyWith(hive: BackendState.initializing);
        emitUpdate(
          newState: bloc.state.copyWith(backendStatus: status),
          groupsToRebuild: {StorageBloc.groupInit},
        );

        if (config.hivePath != null) {
          await Hive.initFlutter(config.hivePath);
        } else {
          await Hive.initFlutter();
        }

        // Register adapters
        for (final adapter in config.hiveAdapters) {
          if (!Hive.isAdapterRegistered(adapter.typeId)) {
            Hive.registerAdapter(adapter);
          }
        }

        // Initialize CacheIndex (uses Hive internally, must be after Hive.initFlutter)
        // This must happen before opening user boxes so TTL tracking is ready
        await cacheIndex.init();

        // Open configured boxes
        final hiveBoxes = <String, BoxInfo>{};
        for (final boxName in config.hiveBoxesToOpen) {
          final hiveAdapter = await HiveAdapterFactory.open<dynamic>(boxName);
          hiveBoxes[boxName] = BoxInfo(
            name: boxName,
            entryCount: hiveAdapter.length,
          );
        }

        status = status.copyWith(hive: BackendState.ready);
        emitUpdate(
          newState:
              bloc.state.copyWith(backendStatus: status, hiveBoxes: hiveBoxes),
          groupsToRebuild: {StorageBloc.groupInit},
        );
      } catch (e) {
        status = status.copyWith(hive: BackendState.error);
        emitUpdate(
          newState: bloc.state.copyWith(
            backendStatus: status,
            lastError: StorageError(
              message: 'Hive initialization failed: $e',
              type: StorageErrorType.backendNotAvailable,
              timestamp: DateTime.now(),
            ),
          ),
          groupsToRebuild: {StorageBloc.groupInit},
        );
      }

      // 2. Initialize SharedPreferences
      try {
        status = status.copyWith(prefs: BackendState.initializing);
        emitUpdate(
          newState: bloc.state.copyWith(backendStatus: status),
          groupsToRebuild: {StorageBloc.groupInit},
        );

        final prefs = await SharedPreferences.getInstance();
        PrefsAdapterFactory.init(
          prefs: prefs,
          keyPrefix: config.prefsKeyPrefix,
        );

        status = status.copyWith(prefs: BackendState.ready);
        emitUpdate(
          newState: bloc.state.copyWith(backendStatus: status),
          groupsToRebuild: {StorageBloc.groupInit},
        );
      } catch (e) {
        status = status.copyWith(prefs: BackendState.error);
        emitUpdate(
          newState: bloc.state.copyWith(
            backendStatus: status,
            lastError: StorageError(
              message: 'SharedPreferences initialization failed: $e',
              type: StorageErrorType.backendNotAvailable,
              timestamp: DateTime.now(),
            ),
          ),
          groupsToRebuild: {StorageBloc.groupInit},
        );
      }

      // 3. Initialize SQLite
      try {
        status = status.copyWith(sqlite: BackendState.initializing);
        emitUpdate(
          newState: bloc.state.copyWith(backendStatus: status),
          groupsToRebuild: {StorageBloc.groupInit},
        );

        final gateway = await SqliteGatewayFactory.init(
          databaseName: config.sqliteDatabaseName,
          version: config.sqliteDatabaseVersion,
          onCreate: config.sqliteOnCreate,
          onUpgrade: config.sqliteOnUpgrade,
        );

        // Get table info
        final tableNames = await gateway.getTableNames();
        final sqliteTables = <String, TableInfo>{};
        for (final name in tableNames) {
          final count = await gateway.getRowCount(name);
          sqliteTables[name] = TableInfo(name: name, rowCount: count);
        }

        status = status.copyWith(sqlite: BackendState.ready);
        emitUpdate(
          newState: bloc.state
              .copyWith(backendStatus: status, sqliteTables: sqliteTables),
          groupsToRebuild: {StorageBloc.groupInit},
        );
      } catch (e) {
        status = status.copyWith(sqlite: BackendState.error);
        emitUpdate(
          newState: bloc.state.copyWith(
            backendStatus: status,
            lastError: StorageError(
              message: 'SQLite initialization failed: $e',
              type: StorageErrorType.sqliteError,
              timestamp: DateTime.now(),
            ),
          ),
          groupsToRebuild: {StorageBloc.groupInit},
        );
      }

      // 4. Initialize Secure Storage
      try {
        status = status.copyWith(secure: BackendState.initializing);
        emitUpdate(
          newState: bloc.state.copyWith(backendStatus: status),
          groupsToRebuild: {StorageBloc.groupInit},
        );

        final isAvailable = await SecureAdapterFactory.isAvailable();
        if (isAvailable) {
          SecureAdapterFactory.init(
            iOSOptions: config.secureStorageIOS,
            androidOptions: config.secureStorageAndroid,
          );
          status = status.copyWith(secure: BackendState.ready);
        } else {
          status = status.copyWith(secure: BackendState.error);
        }

        emitUpdate(
          newState: bloc.state.copyWith(
            backendStatus: status,
            secureStorageAvailable: isAvailable,
          ),
          groupsToRebuild: {StorageBloc.groupInit},
        );
      } catch (e) {
        status = status.copyWith(secure: BackendState.error);
        emitUpdate(
          newState: bloc.state.copyWith(
            backendStatus: status,
            secureStorageAvailable: false,
            lastError: StorageError(
              message: 'Secure storage initialization failed: $e',
              type: StorageErrorType.platformNotSupported,
              timestamp: DateTime.now(),
            ),
          ),
          groupsToRebuild: {StorageBloc.groupInit},
        );
      }

      // Mark as initialized
      emitUpdate(
        newState:
            bloc.state.copyWith(isInitialized: true, clearLastError: true),
        groupsToRebuild: {StorageBloc.groupInit},
      );

      event.succeed(null);
    } catch (e, st) {
      emitFailure(
        error: e,
        errorStackTrace: st,
      );
      event.fail(
        StorageException(
          'Initialization failed',
          type: StorageErrorType.backendNotAvailable,
          cause: e,
        ),
        st,
      );
    }
  }
}
