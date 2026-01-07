import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:juice_storage/src/adapters/prefs_adapter.dart';
import 'package:juice_storage/src/cache/cache_index.dart';
import 'package:juice_storage/src/cache/cache_metadata.dart';
import 'package:juice_storage/src/storage_bloc.dart';
import 'package:juice_storage/src/storage_config.dart';
import 'package:juice_storage/src/storage_events.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tempDir;
  late CacheIndex cacheIndex;

  setUpAll(() async {
    // Create a temp directory for Hive (needed for CacheIndex)
    tempDir = await Directory.systemTemp.createTemp('prefs_use_case_test_');
    Hive.init(tempDir.path);

    // Always try to register the adapter - Hive handles duplicates
    try {
      Hive.registerAdapter(CacheMetadataAdapter());
    } catch (_) {
      // Adapter may already be registered from another test file
    }
  });

  tearDownAll(() async {
    // Don't call Hive.close() as it resets adapter registry for other tests
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    // Mock SharedPreferences
    SharedPreferences.setMockInitialValues({});

    // Initialize cacheIndex
    cacheIndex = CacheIndex();
    await cacheIndex.init();

    // Reset adapters
    PrefsAdapterFactory.reset();
  });

  tearDown(() async {
    if (cacheIndex.isInitialized) {
      await cacheIndex.close();
    }
    try {
      await Hive.deleteBoxFromDisk('_juice_cache_metadata');
    } catch (_) {}
  });

  group('PrefsWriteUseCase', () {
    test('writes string value', () async {
      final prefs = await SharedPreferences.getInstance();
      PrefsAdapterFactory.init(prefs: prefs, keyPrefix: 'test_');

      final bloc = StorageBloc(
        config: const StorageConfig(prefsKeyPrefix: 'test_'),
        cacheIndex: cacheIndex,
      );

      final writeEvent = PrefsWriteEvent(key: 'name', value: 'John');
      bloc.send(writeEvent);
      await writeEvent.result;

      // Verify by reading directly from prefs
      expect(prefs.getString('test_name'), 'John');

      await bloc.close();
    });

    test('writes int value', () async {
      final prefs = await SharedPreferences.getInstance();
      PrefsAdapterFactory.init(prefs: prefs, keyPrefix: 'test_');

      final bloc = StorageBloc(
        config: const StorageConfig(prefsKeyPrefix: 'test_'),
        cacheIndex: cacheIndex,
      );

      final writeEvent = PrefsWriteEvent(key: 'count', value: 42);
      bloc.send(writeEvent);
      await writeEvent.result;

      expect(prefs.getInt('test_count'), 42);

      await bloc.close();
    });

    test('writes with TTL', () async {
      final prefs = await SharedPreferences.getInstance();
      PrefsAdapterFactory.init(prefs: prefs, keyPrefix: 'test_');

      final bloc = StorageBloc(
        config: const StorageConfig(prefsKeyPrefix: 'test_'),
        cacheIndex: cacheIndex,
      );

      final writeEvent = PrefsWriteEvent(
        key: 'cached',
        value: 'value',
        ttl: const Duration(hours: 1),
      );
      bloc.send(writeEvent);
      await writeEvent.result;

      // Verify TTL metadata was set
      final storageKey = cacheIndex.canonicalKey('prefs', 'cached');
      final metadata = cacheIndex.getMetadata(storageKey);
      expect(metadata, isNotNull);
      // Check that expiry is about 1 hour from now
      final expiresIn = metadata!.expiresAt.difference(DateTime.now());
      expect(expiresIn.inMinutes, greaterThanOrEqualTo(59));
      expect(expiresIn.inMinutes, lessThanOrEqualTo(60));

      await bloc.close();
    });

    test('fails when writing null value', () async {
      final prefs = await SharedPreferences.getInstance();
      PrefsAdapterFactory.init(prefs: prefs, keyPrefix: 'test_');

      final bloc = StorageBloc(
        config: const StorageConfig(prefsKeyPrefix: 'test_'),
        cacheIndex: cacheIndex,
      );

      final writeEvent = PrefsWriteEvent(key: 'nullKey', value: null);
      bloc.send(writeEvent);

      expect(writeEvent.result, throwsA(isA<Exception>()));

      await bloc.close();
    });

    test('fails when prefs not initialized', () async {
      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      final writeEvent = PrefsWriteEvent(key: 'key', value: 'value');
      bloc.send(writeEvent);

      expect(writeEvent.result, throwsA(isA<Exception>()));

      await bloc.close();
    });
  });

  group('PrefsReadUseCase', () {
    test('reads existing value', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('test_greeting', 'Hello');

      PrefsAdapterFactory.init(prefs: prefs, keyPrefix: 'test_');

      final bloc = StorageBloc(
        config: const StorageConfig(prefsKeyPrefix: 'test_'),
        cacheIndex: cacheIndex,
      );

      final readEvent = PrefsReadEvent(key: 'greeting');
      bloc.send(readEvent);
      final result = await readEvent.result;

      expect(result, 'Hello');

      await bloc.close();
    });

    test('returns null for missing key', () async {
      final prefs = await SharedPreferences.getInstance();
      PrefsAdapterFactory.init(prefs: prefs, keyPrefix: 'test_');

      final bloc = StorageBloc(
        config: const StorageConfig(prefsKeyPrefix: 'test_'),
        cacheIndex: cacheIndex,
      );

      final readEvent = PrefsReadEvent(key: 'missing');
      bloc.send(readEvent);
      final result = await readEvent.result;

      expect(result, isNull);

      await bloc.close();
    });

    test('performs lazy eviction for expired TTL', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('test_expired', 'old_value');

      PrefsAdapterFactory.init(prefs: prefs, keyPrefix: 'test_');

      final bloc = StorageBloc(
        config: const StorageConfig(prefsKeyPrefix: 'test_'),
        cacheIndex: cacheIndex,
      );

      // Set up expired TTL
      final storageKey = cacheIndex.canonicalKey('prefs', 'expired');
      final pastTime = DateTime.now().subtract(const Duration(hours: 2));
      cacheIndex.clock = () => pastTime;
      await cacheIndex.setExpiry(storageKey, const Duration(hours: 1));
      cacheIndex.clock = () => DateTime.now();

      // Read should return null and delete the data
      final readEvent = PrefsReadEvent(key: 'expired');
      bloc.send(readEvent);
      final result = await readEvent.result;

      expect(result, isNull);

      // Verify data was deleted
      expect(prefs.getString('test_expired'), isNull);

      await bloc.close();
    });
  });

  group('PrefsDeleteUseCase', () {
    test('deletes existing value', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('test_toDelete', 'value');

      PrefsAdapterFactory.init(prefs: prefs, keyPrefix: 'test_');

      final bloc = StorageBloc(
        config: const StorageConfig(prefsKeyPrefix: 'test_'),
        cacheIndex: cacheIndex,
      );

      final deleteEvent = PrefsDeleteEvent(key: 'toDelete');
      bloc.send(deleteEvent);
      await deleteEvent.result;

      expect(prefs.getString('test_toDelete'), isNull);

      await bloc.close();
    });

    test('removes TTL metadata on delete', () async {
      final prefs = await SharedPreferences.getInstance();
      PrefsAdapterFactory.init(prefs: prefs, keyPrefix: 'test_');

      final bloc = StorageBloc(
        config: const StorageConfig(prefsKeyPrefix: 'test_'),
        cacheIndex: cacheIndex,
      );

      // Write with TTL
      final writeEvent = PrefsWriteEvent(
        key: 'ttlKey',
        value: 'value',
        ttl: const Duration(hours: 1),
      );
      bloc.send(writeEvent);
      await writeEvent.result;

      final storageKey = cacheIndex.canonicalKey('prefs', 'ttlKey');
      expect(cacheIndex.getMetadata(storageKey), isNotNull);

      // Delete
      final deleteEvent = PrefsDeleteEvent(key: 'ttlKey');
      bloc.send(deleteEvent);
      await deleteEvent.result;

      expect(cacheIndex.getMetadata(storageKey), isNull);

      await bloc.close();
    });
  });
}
