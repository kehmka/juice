/// Abstract interface for SQLite operations.
///
/// SQLite is fundamentally query-based, not key-value. This interface
/// reflects that paradigm rather than forcing it into [KeyValueAdapter].
///
/// **Note:** Gateways are internal implementation details. Public consumers
/// should use StorageBloc helpers or events.
abstract class SqliteGateway {
  /// Execute a SELECT query.
  ///
  /// Returns a list of rows as maps.
  Future<List<Map<String, dynamic>>> query(
    String sql, [
    List<dynamic>? arguments,
  ]);

  /// Insert a row into a table.
  ///
  /// Returns the row ID of the inserted row.
  Future<int> insert(String table, Map<String, dynamic> values);

  /// Update rows in a table.
  ///
  /// Returns the number of rows affected.
  Future<int> update(
    String table,
    Map<String, dynamic> values, {
    String? where,
    List<dynamic>? whereArgs,
  });

  /// Delete rows from a table.
  ///
  /// Returns the number of rows deleted.
  Future<int> delete(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
  });

  /// Execute raw SQL (INSERT, UPDATE, DELETE, CREATE, etc.).
  Future<void> execute(String sql, [List<dynamic>? arguments]);

  /// Close the database connection.
  Future<void> close();

  /// Whether the database is open.
  bool get isOpen;
}
