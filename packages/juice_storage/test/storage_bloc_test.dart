import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:juice_storage/src/adapters/hive_adapter.dart';
import 'package:juice_storage/src/adapters/prefs_adapter.dart';
import 'package:juice_storage/src/cache/cache_index.dart';
import 'package:juice_storage/src/cache/cache_metadata.dart';
import 'package:juice_storage/src/storage_bloc.dart';
import 'package:juice_storage/src/storage_config.dart';
import 'package:juice_storage/src/storage_events.dart';
import 'package:juice_storage/src/storage_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Helper to ensure CacheMetadata adapter is registered.
void _ensureAdapterRegistered() {
  try {
    if (!Hive.isAdapterRegistered(900)) {
      Hive.registerAdapter(CacheMetadataAdapter());
    }
  } catch (_) {
    // Try direct registration if isAdapterRegistered fails
    try {
      Hive.registerAdapter(CacheMetadataAdapter());
    } catch (_) {
      // Already registered
    }
  }
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('storage_bloc_test_');
    Hive.init(tempDir.path);
    _ensureAdapterRegistered();
  });

  tearDownAll(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await HiveAdapterFactory.closeAll();
    PrefsAdapterFactory.reset();
    _ensureAdapterRegistered();
  });

  tearDown(() async {
    try {
      await Hive.deleteBoxFromDisk('_juice_cache_metadata');
    } catch (_) {}
    try {
      await Hive.deleteBoxFromDisk('testBox');
    } catch (_) {}
    try {
      await Hive.deleteBoxFromDisk('cache');
    } catch (_) {}
  });

  group('StorageBloc', () {
    group('construction', () {
      test('creates with default state', () async {
        final bloc = StorageBloc(
          config: const StorageConfig(),
        );

        expect(bloc.state, const StorageState());
        expect(bloc.state.isInitialized, isFalse);

        await bloc.close();
      });

      test('exposes config', () async {
        const config = StorageConfig(
          prefsKeyPrefix: 'custom_',
          hivePath: '/tmp/custom',
        );
        final bloc = StorageBloc(config: config);

        expect(bloc.config.prefsKeyPrefix, 'custom_');
        expect(bloc.config.hivePath, '/tmp/custom');

        await bloc.close();
      });
    });

    group('rebuild groups', () {
      test('groupInit is correct', () {
        expect(StorageBloc.groupInit, 'storage:init');
      });

      test('groupPrefs is correct', () {
        expect(StorageBloc.groupPrefs, 'storage:prefs');
      });

      test('groupSecure is correct', () {
        expect(StorageBloc.groupSecure, 'storage:secure');
      });

      test('groupCache is correct', () {
        expect(StorageBloc.groupCache, 'storage:cache');
      });

      test('groupHive returns correct format', () {
        expect(StorageBloc.groupHive('cache'), 'storage:hive:cache');
        expect(StorageBloc.groupHive('settings'), 'storage:hive:settings');
      });

      test('groupSqlite returns correct format', () {
        expect(StorageBloc.groupSqlite('users'), 'storage:sqlite:users');
        expect(StorageBloc.groupSqlite('products'), 'storage:sqlite:products');
      });
    });

    group('Hive operations via events', () {
      test('open box adds to state', () async {
        final cacheIndex = CacheIndex();
        await cacheIndex.init();

        final bloc = StorageBloc(
          config: const StorageConfig(),
          cacheIndex: cacheIndex,
        );

        final event = HiveOpenBoxEvent(box: 'testBox');
        bloc.send(event);
        await event.result;

        expect(bloc.state.hiveBoxes.containsKey('testBox'), isTrue);

        await bloc.close();
      });

      test('write and read value', () async {
        final cacheIndex = CacheIndex();
        await cacheIndex.init();

        final bloc = StorageBloc(
          config: const StorageConfig(),
          cacheIndex: cacheIndex,
        );

        // Open box
        final openEvent = HiveOpenBoxEvent(box: 'testBox');
        bloc.send(openEvent);
        await openEvent.result;

        // Write
        final writeEvent = HiveWriteEvent(
          box: 'testBox',
          key: 'greeting',
          value: 'Hello',
        );
        bloc.send(writeEvent);
        await writeEvent.result;

        // Read
        final readEvent = HiveReadEvent(box: 'testBox', key: 'greeting');
        bloc.send(readEvent);
        final value = await readEvent.result;

        expect(value, 'Hello');

        await bloc.close();
      });

      test('delete removes value', () async {
        final cacheIndex = CacheIndex();
        await cacheIndex.init();

        final bloc = StorageBloc(
          config: const StorageConfig(),
          cacheIndex: cacheIndex,
        );

        // Open box
        final openEvent = HiveOpenBoxEvent(box: 'testBox');
        bloc.send(openEvent);
        await openEvent.result;

        // Write
        final writeEvent = HiveWriteEvent(
          box: 'testBox',
          key: 'temp',
          value: 'temporary',
        );
        bloc.send(writeEvent);
        await writeEvent.result;

        // Delete
        final deleteEvent = HiveDeleteEvent(box: 'testBox', key: 'temp');
        bloc.send(deleteEvent);
        await deleteEvent.result;

        // Verify deleted
        final readEvent = HiveReadEvent(box: 'testBox', key: 'temp');
        bloc.send(readEvent);
        final value = await readEvent.result;

        expect(value, isNull);

        await bloc.close();
      });
    });

    group('Hive helper methods', () {
      test('hiveWrite and hiveRead work', () async {
        final cacheIndex = CacheIndex();
        await cacheIndex.init();

        final bloc = StorageBloc(
          config: const StorageConfig(),
          cacheIndex: cacheIndex,
        );

        await bloc.hiveOpenBox('cache');
        await bloc.hiveWrite('cache', 'data', {'name': 'Test'});
        final result =
            await bloc.hiveRead<Map<dynamic, dynamic>>('cache', 'data');

        expect(result, {'name': 'Test'});

        await bloc.close();
      });

      test('hiveDelete works', () async {
        final cacheIndex = CacheIndex();
        await cacheIndex.init();

        final bloc = StorageBloc(
          config: const StorageConfig(),
          cacheIndex: cacheIndex,
        );

        await bloc.hiveOpenBox('cache');
        await bloc.hiveWrite('cache', 'toDelete', 'value');
        await bloc.hiveDelete('cache', 'toDelete');
        final result = await bloc.hiveRead<String>('cache', 'toDelete');

        expect(result, isNull);

        await bloc.close();
      });

      test('hiveCloseBox works', () async {
        final cacheIndex = CacheIndex();
        await cacheIndex.init();

        final bloc = StorageBloc(
          config: const StorageConfig(),
          cacheIndex: cacheIndex,
        );

        await bloc.hiveOpenBox('cache');
        expect(bloc.state.hiveBoxes.containsKey('cache'), isTrue);

        await bloc.hiveCloseBox('cache');
        expect(bloc.state.hiveBoxes.containsKey('cache'), isFalse);

        await bloc.close();
      });
    });

    group('SharedPreferences operations', () {
      test('prefsWrite and prefsRead work', () async {
        final prefs = await SharedPreferences.getInstance();
        PrefsAdapterFactory.init(prefs: prefs, keyPrefix: 'test_');

        final cacheIndex = CacheIndex();
        await cacheIndex.init();

        final bloc = StorageBloc(
          config: const StorageConfig(prefsKeyPrefix: 'test_'),
          cacheIndex: cacheIndex,
        );

        await bloc.prefsWrite('theme', 'dark');
        final result = await bloc.prefsRead<String>('theme');

        expect(result, 'dark');

        await bloc.close();
      });

      test('prefsDelete works', () async {
        final prefs = await SharedPreferences.getInstance();
        PrefsAdapterFactory.init(prefs: prefs, keyPrefix: 'test_');

        final cacheIndex = CacheIndex();
        await cacheIndex.init();

        final bloc = StorageBloc(
          config: const StorageConfig(prefsKeyPrefix: 'test_'),
          cacheIndex: cacheIndex,
        );

        await bloc.prefsWrite('toDelete', 'value');
        await bloc.prefsDelete('toDelete');
        final result = await bloc.prefsRead<String>('toDelete');

        expect(result, isNull);

        await bloc.close();
      });
    });

    group('cache cleanup', () {
      test('cleanupExpiredCache returns count', () async {
        final cacheIndex = CacheIndex();
        await cacheIndex.init();

        final bloc = StorageBloc(
          config: const StorageConfig(),
          cacheIndex: cacheIndex,
        );

        final cleaned = await bloc.cleanupExpiredCache();
        expect(cleaned, isA<int>());

        await bloc.close();
      });
    });

    group('ClearAllEvent', () {
      test('clears Hive data', () async {
        final cacheIndex = CacheIndex();
        await cacheIndex.init();

        final bloc = StorageBloc(
          config: const StorageConfig(),
          cacheIndex: cacheIndex,
        );

        await bloc.hiveOpenBox('cache');
        await bloc.hiveWrite('cache', 'key1', 'value1');
        await bloc.hiveWrite('cache', 'key2', 'value2');

        await bloc.clearAll(const ClearAllOptions(
          clearHive: true,
          clearPrefs: false,
          clearSecure: false,
          clearSqlite: false,
        ));

        // Box should still exist but be empty
        expect(bloc.state.hiveBoxes['cache']?.entryCount, 0);

        await bloc.close();
      });
    });
  });
}
