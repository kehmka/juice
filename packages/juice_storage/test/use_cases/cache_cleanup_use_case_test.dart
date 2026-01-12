import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:juice_storage/src/adapters/hive_adapter.dart';
import 'package:juice_storage/src/cache/cache_index.dart';
import 'package:juice_storage/src/cache/cache_metadata.dart';
import 'package:juice_storage/src/storage_bloc.dart';
import 'package:juice_storage/src/storage_config.dart';
import 'package:juice_storage/src/storage_events.dart';

void main() {
  late Directory tempDir;
  late CacheIndex cacheIndex;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('cache_cleanup_test_');
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

  group('CacheCleanupUseCase', () {
    test('returns 0 when runNow is false', () async {
      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      final event = CacheCleanupEvent(runNow: false);
      bloc.send(event);
      final result = await event.result;

      expect(result, 0);

      await bloc.close();
    });

    test('returns 0 when no expired entries', () async {
      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      final event = CacheCleanupEvent(runNow: true);
      bloc.send(event);
      final result = await event.result;

      expect(result, 0);

      await bloc.close();
    });

    test('cleans expired hive entries', () async {
      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      // Open a box and write a value
      final openEvent = HiveOpenBoxEvent(box: 'testBox');
      bloc.send(openEvent);
      await openEvent.result;

      final writeEvent = HiveWriteEvent(
        box: 'testBox',
        key: 'expiredKey',
        value: 'expiredValue',
        ttl: const Duration(hours: 1),
      );
      bloc.send(writeEvent);
      await writeEvent.result;

      // Force expiration
      final pastTime = DateTime.now().subtract(const Duration(hours: 2));
      cacheIndex.clock = () => pastTime;
      await cacheIndex.setExpiry(
        cacheIndex.canonicalKey('hive', 'expiredKey', 'testBox'),
        const Duration(hours: 1),
      );
      cacheIndex.clock = () => DateTime.now();

      // Run cleanup
      final cleanupEvent = CacheCleanupEvent(runNow: true);
      bloc.send(cleanupEvent);
      final cleaned = await cleanupEvent.result;

      expect(cleaned, 1);

      // Verify data was deleted
      final adapter = HiveAdapterFactory.get<dynamic>('testBox');
      expect(await adapter!.read('expiredKey'), isNull);

      await bloc.close();
    });

    test('updates cache stats after cleanup', () async {
      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      final cleanupEvent = CacheCleanupEvent(runNow: true);
      bloc.send(cleanupEvent);
      await cleanupEvent.result;

      expect(bloc.state.cacheStats.lastCleanupAt, isNotNull);

      await bloc.close();
    });

    test('continues on individual entry failure', () async {
      final bloc = StorageBloc(
        config: const StorageConfig(),
        cacheIndex: cacheIndex,
      );

      // Set up expired entries with an invalid storage key pattern
      final pastTime = DateTime.now().subtract(const Duration(hours: 2));
      cacheIndex.clock = () => pastTime;

      // This key has invalid format (missing parts)
      await cacheIndex.setExpiry('hive:broken', const Duration(hours: 1));

      cacheIndex.clock = () => DateTime.now();

      // Cleanup should not throw
      final cleanupEvent = CacheCleanupEvent(runNow: true);
      bloc.send(cleanupEvent);
      final result = await cleanupEvent.result;

      // Result is 0 because the invalid entry couldn't be processed
      expect(result, 0);

      await bloc.close();
    });
  });
}
