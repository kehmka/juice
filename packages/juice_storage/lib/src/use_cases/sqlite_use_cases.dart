import 'package:juice/juice.dart';

import '../adapters/adapters.dart';
import '../storage_bloc.dart';
import '../storage_events.dart';
import '../storage_exceptions.dart';
import '../storage_state.dart';

/// Use case for executing SQLite queries.
class SqliteQueryUseCase extends BlocUseCase<StorageBloc, SqliteQueryEvent> {
  @override
  Future<void> execute(SqliteQueryEvent event) async {
    try {
      final gateway = SqliteGatewayFactory.instance;
      if (gateway == null) {
        throw StorageException(
          'SQLite not initialized',
          type: StorageErrorType.notInitialized,
        );
      }

      final results = await gateway.query(event.sql, event.arguments);

      // Emit status for sendAndWaitResult (no rebuild groups for queries)
      emitUpdate();
      event.succeed(results);
    } catch (e, st) {
      emitFailure(error: e, errorStackTrace: st);
      if (e is StorageException) {
        event.fail(e, st);
      } else {
        event.fail(
          StorageException(
            'SQLite query failed: ${event.sql}',
            type: StorageErrorType.sqliteError,
            cause: e,
          ),
          st,
        );
      }
    }
  }
}

/// Use case for inserting into SQLite.
class SqliteInsertUseCase extends BlocUseCase<StorageBloc, SqliteInsertEvent> {
  @override
  Future<void> execute(SqliteInsertEvent event) async {
    try {
      final gateway = SqliteGatewayFactory.instance;
      if (gateway == null) {
        throw StorageException(
          'SQLite not initialized',
          type: StorageErrorType.notInitialized,
        );
      }

      final rowId = await gateway.insert(event.table, event.values);

      // Update table info
      emitUpdate(
        newState: () {
          final tables = Map<String, TableInfo>.from(bloc.state.sqliteTables);
          final current = tables[event.table];
          if (current != null) {
            tables[event.table] = TableInfo(
              name: current.name,
              rowCount: current.rowCount + 1,
            );
          }
          return bloc.state.copyWith(sqliteTables: tables);
        }(),
        groupsToRebuild: {StorageBloc.groupSqlite(event.table)},
      );

      event.succeed(rowId);
    } catch (e, st) {
      emitFailure(error: e, errorStackTrace: st);
      if (e is StorageException) {
        event.fail(e, st);
      } else {
        event.fail(
          StorageException(
            'SQLite insert failed: ${event.table}',
            type: StorageErrorType.sqliteError,
            cause: e,
          ),
          st,
        );
      }
    }
  }
}

/// Use case for updating SQLite rows.
class SqliteUpdateUseCase extends BlocUseCase<StorageBloc, SqliteUpdateEvent> {
  @override
  Future<void> execute(SqliteUpdateEvent event) async {
    try {
      final gateway = SqliteGatewayFactory.instance;
      if (gateway == null) {
        throw StorageException(
          'SQLite not initialized',
          type: StorageErrorType.notInitialized,
        );
      }

      final rowsAffected = await gateway.update(
        event.table,
        event.values,
        where: event.where,
        whereArgs: event.whereArgs,
      );

      // Note: Unlike insert/delete, updates don't change row count,
      // so we only emit rebuild groups without state changes.
      emitUpdate(
        groupsToRebuild: {StorageBloc.groupSqlite(event.table)},
      );

      event.succeed(rowsAffected);
    } catch (e, st) {
      emitFailure(error: e, errorStackTrace: st);
      if (e is StorageException) {
        event.fail(e, st);
      } else {
        event.fail(
          StorageException(
            'SQLite update failed: ${event.table}',
            type: StorageErrorType.sqliteError,
            cause: e,
          ),
          st,
        );
      }
    }
  }
}

/// Use case for deleting SQLite rows.
class SqliteDeleteUseCase extends BlocUseCase<StorageBloc, SqliteDeleteEvent> {
  @override
  Future<void> execute(SqliteDeleteEvent event) async {
    try {
      final gateway = SqliteGatewayFactory.instance;
      if (gateway == null) {
        throw StorageException(
          'SQLite not initialized',
          type: StorageErrorType.notInitialized,
        );
      }

      final rowsDeleted = await gateway.delete(
        event.table,
        where: event.where,
        whereArgs: event.whereArgs,
      );

      // Update table info
      emitUpdate(
        newState: () {
          final tables = Map<String, TableInfo>.from(bloc.state.sqliteTables);
          final current = tables[event.table];
          if (current != null) {
            tables[event.table] = TableInfo(
              name: current.name,
              rowCount:
                  (current.rowCount - rowsDeleted).clamp(0, current.rowCount),
            );
          }
          return bloc.state.copyWith(sqliteTables: tables);
        }(),
        groupsToRebuild: {StorageBloc.groupSqlite(event.table)},
      );

      event.succeed(rowsDeleted);
    } catch (e, st) {
      emitFailure(error: e, errorStackTrace: st);
      if (e is StorageException) {
        event.fail(e, st);
      } else {
        event.fail(
          StorageException(
            'SQLite delete failed: ${event.table}',
            type: StorageErrorType.sqliteError,
            cause: e,
          ),
          st,
        );
      }
    }
  }
}

/// Use case for executing raw SQL.
class SqliteRawUseCase extends BlocUseCase<StorageBloc, SqliteRawEvent> {
  @override
  Future<void> execute(SqliteRawEvent event) async {
    try {
      final gateway = SqliteGatewayFactory.instance;
      if (gateway == null) {
        throw StorageException(
          'SQLite not initialized',
          type: StorageErrorType.notInitialized,
        );
      }

      await gateway.execute(event.sql, event.arguments);

      // Emit status for sendAndWaitResult
      emitUpdate();
      event.succeed(null);
    } catch (e, st) {
      emitFailure(error: e, errorStackTrace: st);
      if (e is StorageException) {
        event.fail(e, st);
      } else {
        event.fail(
          StorageException(
            'SQLite raw execution failed: ${event.sql}',
            type: StorageErrorType.sqliteError,
            cause: e,
          ),
          st,
        );
      }
    }
  }
}
