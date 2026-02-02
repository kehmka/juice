import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:juice_storage/src/adapters/hive_adapter.dart';
import 'package:juice_storage/src/cache/cache_index.dart';
import 'package:juice_storage/src/cache/cache_metadata.dart';
import 'package:juice_storage/src/storage_bloc.dart';
import 'package:juice_storage/src/storage_config.dart';
import 'package:juice_storage/src/storage_events.dart';

/// Helper to ensure CacheMetadata adapter is registered.
void _ensureAdapterRegistered() {
  try {
    if (!Hive.isAdapterRegistered(900)) {
      Hive.registerAdapter(CacheMetadataAdapter());
    }
  } catch (_) {
    try {
      Hive.registerAdapter(CacheMetadataAdapter());
    } catch (_) {}
  }
}

void main() {
  late Directory tempDir;
  late CacheIndex cacheIndex;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_use_case_test_');
    Hive.init(tempDir.path);
    _ensureAdapterRegistered();
  });

  tearDownAll(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    _ensureAdapterRegistered();
    cacheIndex = CacheIndex();
    await cacheIndex.init();
    await HiveAdapterFactory.closeAll();
  });

  tearDown(() async {
    if (cacheIndex.isInitialized) {
      await cacheIndex.close();
    }
    try {
      await Hive.deleteBoxFromDisk('_juice_cache_metadata');
    } catch (_) {}
    try {
      await Hive.deleteBoxFromDisk('testBox');
    } catch (_) {}
  });

  group('HiveOpenBoxUseCase', () {
    test('opens a box and updates state', () async {
      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      final event = HiveOpenBoxEvent(box: 'testBox');
      bloc.send(event);
      await event.result;

      expect(bloc.state.hiveBoxes.containsKey('testBox'), isTrue);
      expect(bloc.state.hiveBoxes['testBox']!.name, 'testBox');

      await bloc.close();
    });

    test('opens a lazy box', () async {
      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      final event = HiveOpenBoxEvent(box: 'testBox', lazy: true);
      bloc.send(event);
      await event.result;

      expect(bloc.state.hiveBoxes['testBox']!.isLazy, isTrue);

      await bloc.close();
    });
  });

  group('HiveCloseBoxUseCase', () {
    test('closes a box and removes from state', () async {
      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      // First open the box
      final openEvent = HiveOpenBoxEvent(box: 'testBox');
      bloc.send(openEvent);
      await openEvent.result;

      expect(bloc.state.hiveBoxes.containsKey('testBox'), isTrue);

      // Then close it
      final closeEvent = HiveCloseBoxEvent(box: 'testBox');
      bloc.send(closeEvent);
      await closeEvent.result;

      expect(bloc.state.hiveBoxes.containsKey('testBox'), isFalse);

      await bloc.close();
    });
  });

  group('HiveWriteUseCase', () {
    test('writes value to box', () async {
      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      // Open box
      final openEvent = HiveOpenBoxEvent(box: 'testBox');
      bloc.send(openEvent);
      await openEvent.result;

      // Write value
      final writeEvent = HiveWriteEvent(
        box: 'testBox',
        key: 'testKey',
        value: 'testValue',
      );
      bloc.send(writeEvent);
      await writeEvent.result;

      // Verify by reading
      final adapter = HiveAdapterFactory.get<dynamic>('testBox');
      expect(await adapter!.read('testKey'), 'testValue');

      await bloc.close();
    });

    test('writes value with TTL', () async {
      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      // Open box
      final openEvent = HiveOpenBoxEvent(box: 'testBox');
      bloc.send(openEvent);
      await openEvent.result;

      // Write value with TTL
      final writeEvent = HiveWriteEvent(
        box: 'testBox',
        key: 'ttlKey',
        value: 'ttlValue',
        ttl: const Duration(hours: 1),
      );
      bloc.send(writeEvent);
      await writeEvent.result;

      // Verify TTL metadata was set
      final storageKey = cacheIndex.canonicalKey('hive', 'ttlKey', 'testBox');
      final metadata = cacheIndex.getMetadata(storageKey);
      expect(metadata, isNotNull);
      // Check that expiry is about 1 hour from now
      final expiresIn = metadata!.expiresAt.difference(DateTime.now());
      expect(expiresIn.inMinutes, greaterThanOrEqualTo(59));
      expect(expiresIn.inMinutes, lessThanOrEqualTo(60));

      await bloc.close();
    });
  });

  group('HiveReadUseCase', () {
    test('reads value from box', () async {
      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      // Open box
      final openEvent = HiveOpenBoxEvent(box: 'testBox');
      bloc.send(openEvent);
      await openEvent.result;

      // Write value
      final writeEvent = HiveWriteEvent(
        box: 'testBox',
        key: 'readKey',
        value: 'readValue',
      );
      bloc.send(writeEvent);
      await writeEvent.result;

      // Read value
      final readEvent = HiveReadEvent(box: 'testBox', key: 'readKey');
      bloc.send(readEvent);
      final result = await readEvent.result;

      expect(result, 'readValue');

      await bloc.close();
    });

    test('returns null for missing key', () async {
      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      // Open box
      final openEvent = HiveOpenBoxEvent(box: 'testBox');
      bloc.send(openEvent);
      await openEvent.result;

      // Read missing key
      final readEvent = HiveReadEvent(box: 'testBox', key: 'missingKey');
      bloc.send(readEvent);
      final result = await readEvent.result;

      expect(result, isNull);

      await bloc.close();
    });

    test('performs lazy eviction for expired TTL', () async {
      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      // Open box
      final openEvent = HiveOpenBoxEvent(box: 'testBox');
      bloc.send(openEvent);
      await openEvent.result;

      // Write value with TTL
      final writeEvent = HiveWriteEvent(
        box: 'testBox',
        key: 'expiredKey',
        value: 'expiredValue',
        ttl: const Duration(hours: 1),
      );
      bloc.send(writeEvent);
      await writeEvent.result;

      // Manually expire the entry by manipulating the clock
      final storageKey =
          cacheIndex.canonicalKey('hive', 'expiredKey', 'testBox');
      final pastTime = DateTime.now().subtract(const Duration(hours: 2));
      cacheIndex.clock = () => pastTime;

      // Re-set expiry with past clock
      await cacheIndex.setExpiry(storageKey, const Duration(hours: 1));

      // Reset clock to current time
      cacheIndex.clock = () => DateTime.now();

      // Reading should return null and delete the expired data
      final readEvent = HiveReadEvent(box: 'testBox', key: 'expiredKey');
      bloc.send(readEvent);
      final result = await readEvent.result;

      expect(result, isNull);

      // Verify the data was deleted
      final adapter = HiveAdapterFactory.get<dynamic>('testBox');
      expect(await adapter!.read('expiredKey'), isNull);

      await bloc.close();
    });

    test('bloc.clock controls TTL expiration', () async {
      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      // Set clock to a known time
      var testTime = DateTime(2025, 6, 1, 12, 0);
      bloc.clock = () => testTime;

      // Open box
      final openEvent = HiveOpenBoxEvent(box: 'testBox');
      bloc.send(openEvent);
      await openEvent.result;

      // Write value with 1 hour TTL (at testTime)
      final writeEvent = HiveWriteEvent(
        box: 'testBox',
        key: 'clockKey',
        value: 'clockValue',
        ttl: const Duration(hours: 1),
      );
      bloc.send(writeEvent);
      await writeEvent.result;

      // Still within TTL: read should return value
      testTime = DateTime(2025, 6, 1, 12, 30);
      final readEvent1 = HiveReadEvent(box: 'testBox', key: 'clockKey');
      bloc.send(readEvent1);
      expect(await readEvent1.result, 'clockValue');

      // Advance past TTL: read should return null
      testTime = DateTime(2025, 6, 1, 14, 0);
      final readEvent2 = HiveReadEvent(box: 'testBox', key: 'clockKey');
      bloc.send(readEvent2);
      expect(await readEvent2.result, isNull);

      await bloc.close();
    });

    test('fails for unopened box', () async {
      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      final readEvent = HiveReadEvent(box: 'unopenedBox', key: 'key');
      bloc.send(readEvent);

      expect(readEvent.result, throwsA(isA<Exception>()));

      await bloc.close();
    });
  });

  group('HiveDeleteUseCase', () {
    test('deletes value from box', () async {
      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      // Open box
      final openEvent = HiveOpenBoxEvent(box: 'testBox');
      bloc.send(openEvent);
      await openEvent.result;

      // Write value
      final writeEvent = HiveWriteEvent(
        box: 'testBox',
        key: 'deleteKey',
        value: 'deleteValue',
      );
      bloc.send(writeEvent);
      await writeEvent.result;

      // Delete value
      final deleteEvent = HiveDeleteEvent(box: 'testBox', key: 'deleteKey');
      bloc.send(deleteEvent);
      await deleteEvent.result;

      // Verify deletion
      final adapter = HiveAdapterFactory.get<dynamic>('testBox');
      expect(await adapter!.read('deleteKey'), isNull);

      await bloc.close();
    });

    test('removes TTL metadata on delete', () async {
      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      // Open box
      final openEvent = HiveOpenBoxEvent(box: 'testBox');
      bloc.send(openEvent);
      await openEvent.result;

      // Write value with TTL
      final writeEvent = HiveWriteEvent(
        box: 'testBox',
        key: 'ttlDeleteKey',
        value: 'value',
        ttl: const Duration(hours: 1),
      );
      bloc.send(writeEvent);
      await writeEvent.result;

      // Verify TTL was set
      final storageKey =
          cacheIndex.canonicalKey('hive', 'ttlDeleteKey', 'testBox');
      expect(cacheIndex.getMetadata(storageKey), isNotNull);

      // Delete value
      final deleteEvent = HiveDeleteEvent(box: 'testBox', key: 'ttlDeleteKey');
      bloc.send(deleteEvent);
      await deleteEvent.result;

      // Verify TTL was removed
      expect(cacheIndex.getMetadata(storageKey), isNull);

      await bloc.close();
    });
  });
}
