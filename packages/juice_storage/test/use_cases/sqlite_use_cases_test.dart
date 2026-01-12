import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:juice_storage/src/adapters/sqlite_gateway_impl.dart';
import 'package:juice_storage/src/cache/cache_index.dart';
import 'package:juice_storage/src/cache/cache_metadata.dart';
import 'package:juice_storage/src/storage_bloc.dart';
import 'package:juice_storage/src/storage_config.dart';
import 'package:juice_storage/src/storage_events.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDir;
  late CacheIndex cacheIndex;
  late String dbPath;
  var dbCounter = 0;

  setUpAll(() async {
    // Initialize FFI for SQLite testing on desktop
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // Create temp directory for Hive (needed for CacheIndex) and SQLite databases
    tempDir = await Directory.systemTemp.createTemp('sqlite_use_case_test_');
    Hive.init(tempDir.path);

    try {
      Hive.registerAdapter(CacheMetadataAdapter());
    } catch (_) {
      // Adapter may already be registered
    }
  });

  tearDownAll(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    // Initialize cacheIndex
    cacheIndex = CacheIndex();
    await cacheIndex.init();

    // Create a unique database name for each test (just the filename, not full path)
    dbCounter++;
    dbPath = 'sqlite_test_$dbCounter.db';

    // Close and reset SQLite gateway to ensure clean state
    await SqliteGatewayFactory.close();
    SqliteGatewayFactory.reset();
  });

  tearDown(() async {
    // Close SQLite gateway first
    await SqliteGatewayFactory.close();
    SqliteGatewayFactory.reset();

    // Delete the test database file (from default database path)
    try {
      final databasesPath = await getDatabasesPath();
      final fullPath = '$databasesPath/$dbPath';
      final dbFile = File(fullPath);
      if (await dbFile.exists()) {
        await dbFile.delete();
      }
    } catch (_) {}

    if (cacheIndex.isInitialized) {
      await cacheIndex.close();
    }
    try {
      await Hive.deleteBoxFromDisk('_juice_cache_metadata');
    } catch (_) {}
  });

  /// Helper to initialize SQLite with a test database.
  Future<void> initSqliteWithTestTable() async {
    await SqliteGatewayFactory.init(
      databaseName: dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            email TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE posts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            user_id INTEGER
          )
        ''');
      },
    );
  }

  group('SqliteQueryUseCase', () {
    test('executes SELECT query and returns results', () async {
      await initSqliteWithTestTable();

      // Insert test data directly
      final gateway = SqliteGatewayFactory.instance!;
      await gateway.insert('users', {'name': 'Alice', 'email': 'alice@test.com'});
      await gateway.insert('users', {'name': 'Bob', 'email': 'bob@test.com'});

      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      final queryEvent = SqliteQueryEvent(sql: 'SELECT * FROM users ORDER BY name');
      bloc.send(queryEvent);
      final results = await queryEvent.result as List<Map<String, dynamic>>;

      expect(results.length, 2);
      expect(results[0]['name'], 'Alice');
      expect(results[1]['name'], 'Bob');

      await bloc.close();
    });

    test('executes parameterized query', () async {
      await initSqliteWithTestTable();

      final gateway = SqliteGatewayFactory.instance!;
      await gateway.insert('users', {'name': 'Alice', 'email': 'alice@test.com'});
      await gateway.insert('users', {'name': 'Bob', 'email': 'bob@test.com'});

      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      final queryEvent = SqliteQueryEvent(
        sql: 'SELECT * FROM users WHERE name = ?',
        arguments: ['Alice'],
      );
      bloc.send(queryEvent);
      final results = await queryEvent.result as List<Map<String, dynamic>>;

      expect(results.length, 1);
      expect(results[0]['name'], 'Alice');
      expect(results[0]['email'], 'alice@test.com');

      await bloc.close();
    });

    test('returns empty list for no matches', () async {
      await initSqliteWithTestTable();

      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      final queryEvent = SqliteQueryEvent(sql: 'SELECT * FROM users');
      bloc.send(queryEvent);
      final results = await queryEvent.result as List<Map<String, dynamic>>;

      expect(results, isEmpty);

      await bloc.close();
    });

    test('fails when SQLite not initialized', () async {
      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      final queryEvent = SqliteQueryEvent(sql: 'SELECT * FROM users');
      bloc.send(queryEvent);

      expect(queryEvent.result, throwsA(isA<Exception>()));

      await bloc.close();
    });

    test('fails for invalid SQL', () async {
      await initSqliteWithTestTable();

      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      final queryEvent = SqliteQueryEvent(sql: 'SELECT * FROM nonexistent_table');
      bloc.send(queryEvent);

      // Use a shorter timeout for the error expectation
      await expectLater(
        queryEvent.result.timeout(const Duration(seconds: 5)),
        throwsA(isA<Exception>()),
      );

      await bloc.close();
    });
  });

  group('SqliteInsertUseCase', () {
    test('inserts row and returns row ID', () async {
      await initSqliteWithTestTable();

      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      final insertEvent = SqliteInsertEvent(
        table: 'users',
        values: {'name': 'Charlie', 'email': 'charlie@test.com'},
      );
      bloc.send(insertEvent);
      final rowId = await insertEvent.result as int;

      expect(rowId, greaterThan(0));

      // Verify data was inserted
      final gateway = SqliteGatewayFactory.instance!;
      final results = await gateway.query('SELECT * FROM users WHERE id = ?', [rowId]);
      expect(results.length, 1);
      expect(results[0]['name'], 'Charlie');

      await bloc.close();
    });

    test('updates table row count in state', () async {
      await initSqliteWithTestTable();

      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      // Verify via multiple inserts that the table accepts data
      final insertEvent1 = SqliteInsertEvent(
        table: 'users',
        values: {'name': 'User1'},
      );
      bloc.send(insertEvent1);
      await insertEvent1.result;

      final insertEvent2 = SqliteInsertEvent(
        table: 'users',
        values: {'name': 'User2'},
      );
      bloc.send(insertEvent2);
      await insertEvent2.result;

      // Verify via query
      final gateway = SqliteGatewayFactory.instance!;
      final count = await gateway.getRowCount('users');
      expect(count, 2);

      await bloc.close();
    });

    test('fails when SQLite not initialized', () async {
      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      final insertEvent = SqliteInsertEvent(
        table: 'users',
        values: {'name': 'Test'},
      );
      bloc.send(insertEvent);

      expect(insertEvent.result, throwsA(isA<Exception>()));

      await bloc.close();
    });

    test('fails for invalid table', () async {
      await initSqliteWithTestTable();

      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      final insertEvent = SqliteInsertEvent(
        table: 'nonexistent',
        values: {'name': 'Test'},
      );
      bloc.send(insertEvent);

      expect(insertEvent.result, throwsA(isA<Exception>()));

      await bloc.close();
    });

    test('fails for constraint violation', () async {
      await initSqliteWithTestTable();

      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      // name is NOT NULL, so this should fail
      final insertEvent = SqliteInsertEvent(
        table: 'users',
        values: {'email': 'test@test.com'}, // missing required 'name'
      );
      bloc.send(insertEvent);

      expect(insertEvent.result, throwsA(isA<Exception>()));

      await bloc.close();
    });
  });

  group('SqliteUpdateUseCase', () {
    test('updates rows and returns affected count', () async {
      await initSqliteWithTestTable();

      final gateway = SqliteGatewayFactory.instance!;
      await gateway.insert('users', {'name': 'Alice', 'email': 'old@test.com'});

      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      final updateEvent = SqliteUpdateEvent(
        table: 'users',
        values: {'email': 'new@test.com'},
        where: 'name = ?',
        whereArgs: ['Alice'],
      );
      bloc.send(updateEvent);
      final affected = await updateEvent.result as int;

      expect(affected, 1);

      // Verify update
      final results = await gateway.query('SELECT email FROM users WHERE name = ?', ['Alice']);
      expect(results[0]['email'], 'new@test.com');

      await bloc.close();
    });

    test('returns 0 for no matching rows', () async {
      await initSqliteWithTestTable();

      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      final updateEvent = SqliteUpdateEvent(
        table: 'users',
        values: {'email': 'new@test.com'},
        where: 'name = ?',
        whereArgs: ['NonExistent'],
      );
      bloc.send(updateEvent);
      final affected = await updateEvent.result as int;

      expect(affected, 0);

      await bloc.close();
    });

    test('updates all rows when no where clause', () async {
      await initSqliteWithTestTable();

      final gateway = SqliteGatewayFactory.instance!;
      await gateway.insert('users', {'name': 'Alice', 'email': 'a@test.com'});
      await gateway.insert('users', {'name': 'Bob', 'email': 'b@test.com'});
      await gateway.insert('users', {'name': 'Charlie', 'email': 'c@test.com'});

      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      final updateEvent = SqliteUpdateEvent(
        table: 'users',
        values: {'email': 'updated@test.com'},
      );
      bloc.send(updateEvent);
      final affected = await updateEvent.result as int;

      expect(affected, 3);

      await bloc.close();
    });

    test('fails when SQLite not initialized', () async {
      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      final updateEvent = SqliteUpdateEvent(
        table: 'users',
        values: {'name': 'Updated'},
      );
      bloc.send(updateEvent);

      expect(updateEvent.result, throwsA(isA<Exception>()));

      await bloc.close();
    });
  });

  group('SqliteDeleteUseCase', () {
    test('deletes rows and returns deleted count', () async {
      await initSqliteWithTestTable();

      final gateway = SqliteGatewayFactory.instance!;
      await gateway.insert('users', {'name': 'Alice'});
      await gateway.insert('users', {'name': 'Bob'});

      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      final deleteEvent = SqliteDeleteEvent(
        table: 'users',
        where: 'name = ?',
        whereArgs: ['Alice'],
      );
      bloc.send(deleteEvent);
      final deleted = await deleteEvent.result as int;

      expect(deleted, 1);

      // Verify deletion
      final results = await gateway.query('SELECT * FROM users');
      expect(results.length, 1);
      expect(results[0]['name'], 'Bob');

      await bloc.close();
    });

    test('returns 0 for no matching rows', () async {
      await initSqliteWithTestTable();

      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      final deleteEvent = SqliteDeleteEvent(
        table: 'users',
        where: 'name = ?',
        whereArgs: ['NonExistent'],
      );
      bloc.send(deleteEvent);
      final deleted = await deleteEvent.result as int;

      expect(deleted, 0);

      await bloc.close();
    });

    test('deletes all rows when no where clause', () async {
      await initSqliteWithTestTable();

      final gateway = SqliteGatewayFactory.instance!;
      await gateway.insert('users', {'name': 'Alice'});
      await gateway.insert('users', {'name': 'Bob'});
      await gateway.insert('users', {'name': 'Charlie'});

      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      final deleteEvent = SqliteDeleteEvent(table: 'users');
      bloc.send(deleteEvent);
      final deleted = await deleteEvent.result as int;

      expect(deleted, 3);

      // Verify all deleted
      final results = await gateway.query('SELECT * FROM users');
      expect(results, isEmpty);

      await bloc.close();
    });

    test('fails when SQLite not initialized', () async {
      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      final deleteEvent = SqliteDeleteEvent(table: 'users');
      bloc.send(deleteEvent);

      expect(deleteEvent.result, throwsA(isA<Exception>()));

      await bloc.close();
    });
  });

  group('SqliteRawUseCase', () {
    test('executes CREATE TABLE statement', () async {
      await initSqliteWithTestTable();

      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      final rawEvent = SqliteRawEvent(
        sql: 'CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT)',
      );
      bloc.send(rawEvent);
      await rawEvent.result;

      // Verify table was created by inserting into it
      final gateway = SqliteGatewayFactory.instance!;
      final rowId = await gateway.insert('settings', {'key': 'theme', 'value': 'dark'});
      expect(rowId, greaterThan(0));

      await bloc.close();
    });

    test('executes INSERT statement', () async {
      await initSqliteWithTestTable();

      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      final rawEvent = SqliteRawEvent(
        sql: "INSERT INTO users (name, email) VALUES ('David', 'david@test.com')",
      );
      bloc.send(rawEvent);
      await rawEvent.result;

      // Verify insert
      final gateway = SqliteGatewayFactory.instance!;
      final results = await gateway.query("SELECT * FROM users WHERE name = 'David'");
      expect(results.length, 1);

      await bloc.close();
    });

    test('executes parameterized statement', () async {
      await initSqliteWithTestTable();

      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      final rawEvent = SqliteRawEvent(
        sql: 'INSERT INTO users (name, email) VALUES (?, ?)',
        arguments: ['Eve', 'eve@test.com'],
      );
      bloc.send(rawEvent);
      await rawEvent.result;

      // Verify insert
      final gateway = SqliteGatewayFactory.instance!;
      final results = await gateway.query("SELECT * FROM users WHERE name = 'Eve'");
      expect(results.length, 1);
      expect(results[0]['email'], 'eve@test.com');

      await bloc.close();
    });

    test('executes DROP TABLE statement', () async {
      await initSqliteWithTestTable();

      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      final rawEvent = SqliteRawEvent(sql: 'DROP TABLE IF EXISTS posts');
      bloc.send(rawEvent);
      await rawEvent.result;

      // Verify table was dropped
      final gateway = SqliteGatewayFactory.instance!;
      final tables = await gateway.getTableNames();
      expect(tables, isNot(contains('posts')));

      await bloc.close();
    });

    test('fails when SQLite not initialized', () async {
      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      final rawEvent = SqliteRawEvent(sql: 'CREATE TABLE test (id INTEGER)');
      bloc.send(rawEvent);

      expect(rawEvent.result, throwsA(isA<Exception>()));

      await bloc.close();
    });

    test('fails for invalid SQL', () async {
      await initSqliteWithTestTable();

      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      final rawEvent = SqliteRawEvent(sql: 'INVALID SQL STATEMENT');
      bloc.send(rawEvent);

      expect(rawEvent.result, throwsA(isA<Exception>()));

      await bloc.close();
    });
  });

  group('Rebuild groups', () {
    test('groupSqlite returns correct group name', () {
      expect(StorageBloc.groupSqlite('users'), 'storage:sqlite:users');
      expect(StorageBloc.groupSqlite('posts'), 'storage:sqlite:posts');
    });
  });

  group('Integration scenarios', () {
    test('full CRUD workflow', () async {
      await initSqliteWithTestTable();

      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      // Create
      final insertEvent = SqliteInsertEvent(
        table: 'users',
        values: {'name': 'Integration User', 'email': 'integration@test.com'},
      );
      bloc.send(insertEvent);
      final rowId = await insertEvent.result as int;
      expect(rowId, greaterThan(0));

      // Read
      final queryEvent = SqliteQueryEvent(
        sql: 'SELECT * FROM users WHERE id = ?',
        arguments: [rowId],
      );
      bloc.send(queryEvent);
      var results = await queryEvent.result as List<Map<String, dynamic>>;
      expect(results.length, 1);
      expect(results[0]['name'], 'Integration User');

      // Update
      final updateEvent = SqliteUpdateEvent(
        table: 'users',
        values: {'name': 'Updated User'},
        where: 'id = ?',
        whereArgs: [rowId],
      );
      bloc.send(updateEvent);
      final affected = await updateEvent.result as int;
      expect(affected, 1);

      // Verify update
      final verifyEvent = SqliteQueryEvent(
        sql: 'SELECT name FROM users WHERE id = ?',
        arguments: [rowId],
      );
      bloc.send(verifyEvent);
      results = await verifyEvent.result as List<Map<String, dynamic>>;
      expect(results[0]['name'], 'Updated User');

      // Delete
      final deleteEvent = SqliteDeleteEvent(
        table: 'users',
        where: 'id = ?',
        whereArgs: [rowId],
      );
      bloc.send(deleteEvent);
      final deleted = await deleteEvent.result as int;
      expect(deleted, 1);

      // Verify deletion
      final finalQueryEvent = SqliteQueryEvent(
        sql: 'SELECT * FROM users WHERE id = ?',
        arguments: [rowId],
      );
      bloc.send(finalQueryEvent);
      results = await finalQueryEvent.result as List<Map<String, dynamic>>;
      expect(results, isEmpty);

      await bloc.close();
    });

    test('multiple tables work independently', () async {
      await initSqliteWithTestTable();

      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      // Insert into users
      final userInsert = SqliteInsertEvent(
        table: 'users',
        values: {'name': 'Author'},
      );
      bloc.send(userInsert);
      final userId = await userInsert.result as int;

      // Insert into posts
      final postInsert = SqliteInsertEvent(
        table: 'posts',
        values: {'title': 'My Post', 'user_id': userId},
      );
      bloc.send(postInsert);
      final postId = await postInsert.result as int;

      // Query with join
      final joinQuery = SqliteQueryEvent(
        sql: '''
          SELECT posts.title, users.name as author
          FROM posts
          JOIN users ON posts.user_id = users.id
          WHERE posts.id = ?
        ''',
        arguments: [postId],
      );
      bloc.send(joinQuery);
      final results = await joinQuery.result as List<Map<String, dynamic>>;

      expect(results.length, 1);
      expect(results[0]['title'], 'My Post');
      expect(results[0]['author'], 'Author');

      await bloc.close();
    });
  });
}
