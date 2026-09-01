import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:juice/juice.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../adapters/adapters.dart';
import '../cache/cache_index.dart';
import '../storage_bloc.dart';
import '../storage_config.dart';
import '../storage_events.dart';
import '../storage_exceptions.dart';
import '../storage_state.dart';
import 'serialized_storage_mutation_use_case.dart';

/// Use case for initializing all storage backends.
class InitializeUseCase
    extends SerializedStorageMutationUseCase<InitializeStorageEvent> {
  final StorageConfig config;
  final CacheIndex cacheIndex;

  InitializeUseCase({required this.config, required this.cacheIndex});

  @override
  Future<void> executeMutation(InitializeStorageEvent event) async {
    try {
      var status = const StorageBackendStatus();

      // 1. Initialize Hive — with ONE bounded retry. A process killed
      // mid-write (a dev kill, an OS jetsam) can leave a stale box lock
      // that fails exactly one cold boot; the app then ran a whole
      // session with hive dead and every cache/prefs consumer throwing
      // "CacheIndex not initialized" (observed 2026-09-01, first boot
      // after a killed battery session). One short-delay retry heals the
      // transient class; a real failure still fails — LOUDLY, in the log
      // as well as the state.
      status = status.copyWith(hive: BackendState.initializing);
      emitUpdate(
        newState: bloc.state.copyWith(backendStatus: status),
        groupsToRebuild: {StorageBloc.groupInit},
      );
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
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

          // Initialize CacheIndex (uses Hive internally, must be after
          // Hive.initFlutter). Must happen before opening user boxes so
          // TTL tracking is ready.
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
            newState: bloc.state
                .copyWith(backendStatus: status, hiveBoxes: hiveBoxes),
            groupsToRebuild: {StorageBloc.groupInit},
          );
          break;
        } catch (e, st) {
          if (attempt == 0) {
            JuiceLoggerConfig.logger.log(
                'storage: hive init failed (attempt 1) — retrying once: $e');
            await Future<void>.delayed(const Duration(milliseconds: 300));
            continue;
          }
          JuiceLoggerConfig.logger.logError(
              'storage: hive init failed after retry — the hive-backed '
              'cache is DEAD this session',
              e,
              st);
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

      // Mark as initialized (preserve lastError if a backend failed)
      emitUpdate(
        newState: bloc.state.copyWith(isInitialized: true),
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
