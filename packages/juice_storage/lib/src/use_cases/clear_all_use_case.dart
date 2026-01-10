import 'package:juice/juice.dart';

import '../adapters/adapters.dart';
import '../cache/cache_index.dart';
import '../storage_bloc.dart';
import '../storage_events.dart';
import '../storage_exceptions.dart';
import '../storage_state.dart';

/// Use case for clearing all storage (logout scenario).
///
/// Clears data from all storage backends based on the provided options.
/// This is a destructive operation - use with care.
class ClearAllUseCase extends BlocUseCase<StorageBloc, ClearAllEvent> {
  final CacheIndex cacheIndex;

  ClearAllUseCase({required this.cacheIndex});

  @override
  Future<void> execute(ClearAllEvent event) async {
    final options = event.options;
    final groupsToRebuild = <String>{StorageBloc.groupInit};

    try {
      // 1. Clear Hive
      if (options.clearHive) {
        if (options.hiveBoxesToClear != null) {
          // Clear specific boxes
          for (final boxName in options.hiveBoxesToClear!) {
            final adapter = HiveAdapterFactory.get<dynamic>(boxName);
            if (adapter != null) {
              await adapter.box.clear();
              groupsToRebuild.add(StorageBloc.groupHive(boxName));
            }
          }
        } else {
          // Clear all open boxes
          for (final boxName in HiveAdapterFactory.openBoxes) {
            final adapter = HiveAdapterFactory.get<dynamic>(boxName);
            if (adapter != null) {
              await adapter.box.clear();
              groupsToRebuild.add(StorageBloc.groupHive(boxName));
            }
          }
        }
      }

      // 2. Clear SharedPreferences
      if (options.clearPrefs) {
        final adapter = PrefsAdapterFactory.instance;
        if (adapter != null) {
          await adapter.clear();
          groupsToRebuild.add(StorageBloc.groupPrefs);
        }
      }

      // 3. Clear Secure Storage
      if (options.clearSecure) {
        final adapter = SecureAdapterFactory.instance;
        if (adapter != null) {
          await adapter.clear();
          groupsToRebuild.add(StorageBloc.groupSecure);
        }
      }

      // 4. Clear SQLite
      if (options.clearSqlite) {
        final gateway = SqliteGatewayFactory.instance;
        if (gateway != null) {
          final tableNames = await gateway.getTableNames();
          for (final table in tableNames) {
            if (options.sqliteDropTables) {
              await gateway.dropTable(table);
            } else {
              await gateway.clearTable(table);
            }
            groupsToRebuild.add(StorageBloc.groupSqlite(table));
          }
        }
      }

      // 5. Clear cache metadata
      await cacheIndex.clear();
      groupsToRebuild.add(StorageBloc.groupCache);

      // Update state to reflect cleared storage
      emitUpdate(
        newState: () {
          var newState = bloc.state;

          if (options.clearHive) {
            // Update Hive box info with zero counts
            final boxes = <String, BoxInfo>{};
            for (final entry in bloc.state.hiveBoxes.entries) {
              boxes[entry.key] = BoxInfo(
                name: entry.value.name,
                isLazy: entry.value.isLazy,
                entryCount: 0,
              );
            }
            newState = newState.copyWith(hiveBoxes: boxes);
          }

          if (options.clearSqlite) {
            if (options.sqliteDropTables) {
              // Tables are gone
              newState = newState.copyWith(sqliteTables: const {});
            } else {
              // Tables exist but are empty
              final tables = <String, TableInfo>{};
              for (final entry in bloc.state.sqliteTables.entries) {
                tables[entry.key] =
                    TableInfo(name: entry.value.name, rowCount: 0);
              }
              newState = newState.copyWith(sqliteTables: tables);
            }
          }

          return newState;
        }(),
        groupsToRebuild: groupsToRebuild,
      );

      event.succeed(null);
    } catch (e, st) {
      emitFailure(error: e, errorStackTrace: st);
      event.fail(
        StorageException(
          'Clear all failed',
          type: StorageErrorType.backendNotAvailable,
          cause: e,
        ),
        st,
      );
    }
  }
}
