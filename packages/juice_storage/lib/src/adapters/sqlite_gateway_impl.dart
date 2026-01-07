import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;

import 'sqlite_gateway.dart';

/// sqflite implementation of [SqliteGateway].
class SqliteGatewayImpl implements SqliteGateway {
  SqliteGatewayImpl._(this._db);

  final Database _db;

  /// The underlying database.
  Database get database => _db;

  /// The database path.
  String get databasePath => _db.path;

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, [
    List<dynamic>? arguments,
  ]) async {
    return _db.rawQuery(sql, arguments);
  }

  @override
  Future<int> insert(String table, Map<String, dynamic> values) async {
    return _db.insert(table, values);
  }

  @override
  Future<int> update(
    String table,
    Map<String, dynamic> values, {
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    return _db.update(
      table,
      values,
      where: where,
      whereArgs: whereArgs,
    );
  }

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    return _db.delete(
      table,
      where: where,
      whereArgs: whereArgs,
    );
  }

  @override
  Future<void> execute(String sql, [List<dynamic>? arguments]) async {
    await _db.execute(sql, arguments);
  }

  @override
  Future<void> close() async {
    await _db.close();
  }

  @override
  bool get isOpen => _db.isOpen;

  /// Get table names in the database.
  Future<List<String>> getTableNames() async {
    final result = await _db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
    );
    return result.map((row) => row['name'] as String).toList();
  }

  /// Get row count for a table.
  Future<int> getRowCount(String table) async {
    final result = await _db.rawQuery('SELECT COUNT(*) as count FROM $table');
    return result.first['count'] as int;
  }

  /// Clear all rows from a table (without dropping it).
  Future<void> clearTable(String table) async {
    await _db.delete(table);
  }

  /// Drop a table.
  Future<void> dropTable(String table) async {
    await _db.execute('DROP TABLE IF EXISTS $table');
  }
}

/// Factory for creating SQLite gateway.
class SqliteGatewayFactory {
  SqliteGatewayFactory._();

  static SqliteGatewayImpl? _gateway;

  /// Initialize and get the gateway.
  static Future<SqliteGatewayImpl> init({
    required String databaseName,
    required int version,
    OnDatabaseCreateFn? onCreate,
    OnDatabaseVersionChangeFn? onUpgrade,
  }) async {
    if (_gateway != null && _gateway!.isOpen) {
      return _gateway!;
    }

    final databasesPath = await getDatabasesPath();
    final dbPath = path.join(databasesPath, databaseName);

    final db = await openDatabase(
      dbPath,
      version: version,
      onCreate: onCreate,
      onUpgrade: onUpgrade,
    );

    _gateway = SqliteGatewayImpl._(db);
    return _gateway!;
  }

  /// Get the existing gateway.
  ///
  /// Returns null if not initialized.
  static SqliteGatewayImpl? get instance => _gateway;

  /// Close the gateway.
  static Future<void> close() async {
    if (_gateway != null) {
      await _gateway!.close();
      _gateway = null;
    }
  }

  /// Clear the gateway (for testing).
  static void reset() {
    _gateway = null;
  }
}
