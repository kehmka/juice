import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:juice_storage/src/cache/cache_index.dart';

void main() {
  late CacheIndex cacheIndex;
  late Directory tempDir;

  setUpAll(() async {
    // Create a temp directory for Hive
    tempDir = await Directory.systemTemp.createTemp('hive_test_');
    Hive.init(tempDir.path);
    // Register adapter once for all tests
    CacheIndex.ensureAdapterRegistered();
  });

  tearDownAll(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    cacheIndex = CacheIndex();
  });

  tearDown(() async {
    if (cacheIndex.isInitialized) {
      await cacheIndex.close();
    }
    // Delete the metadata box to start fresh
    try {
      await Hive.deleteBoxFromDisk('_juice_cache_metadata');
    } catch (_) {}
  });

  group('CacheIndex', () {
    group('initialization', () {
      test('isInitialized returns false before init', () {
        expect(cacheIndex.isInitialized, isFalse);
      });

      test('init initializes the cache index', () async {
        await cacheIndex.init();

        expect(cacheIndex.isInitialized, isTrue);
      });

      test('init is idempotent', () async {
        await cacheIndex.init();
        await cacheIndex.init(); // Should not throw

        expect(cacheIndex.isInitialized, isTrue);
      });

      test('close closes the cache index', () async {
        await cacheIndex.init();
        await cacheIndex.close();

        expect(cacheIndex.isInitialized, isFalse);
      });
    });

    group('canonicalKey', () {
      test('generates hive key with box', () {
        final key = cacheIndex.canonicalKey('hive', 'myKey', 'myBox');
        expect(key, 'hive:myBox:myKey');
      });

      test('throws when hive key missing box', () {
        expect(
          () => cacheIndex.canonicalKey('hive', 'myKey'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('generates prefs key', () {
        final key = cacheIndex.canonicalKey('prefs', 'myKey');
        expect(key, 'prefs:myKey');
      });

      test('throws for unsupported backend', () {
        expect(
          () => cacheIndex.canonicalKey('sqlite', 'myKey'),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('setExpiry', () {
      test('sets expiration for a key', () async {
        await cacheIndex.init();

        await cacheIndex.setExpiry('prefs:testKey', const Duration(hours: 1));

        final meta = cacheIndex.getMetadata('prefs:testKey');
        expect(meta, isNotNull);
        expect(meta!.storageKey, 'prefs:testKey');
      });

      test('throws when not initialized', () async {
        expect(
          () => cacheIndex.setExpiry('prefs:key', const Duration(hours: 1)),
          throwsA(isA<StateError>()),
        );
      });
    });

    group('isExpired', () {
      test('returns false when no TTL set', () async {
        await cacheIndex.init();

        expect(cacheIndex.isExpired('prefs:noTTL'), isFalse);
      });

      test('returns false when TTL not expired', () async {
        await cacheIndex.init();
        await cacheIndex.setExpiry('prefs:valid', const Duration(hours: 1));

        expect(cacheIndex.isExpired('prefs:valid'), isFalse);
      });

      test('returns true when TTL expired', () async {
        await cacheIndex.init();

        // Use a custom clock to test expiration
        final pastTime = DateTime.now().subtract(const Duration(hours: 2));
        cacheIndex.clock = () => pastTime;
        await cacheIndex.setExpiry('prefs:expired', const Duration(hours: 1));

        // Reset clock to current time
        cacheIndex.clock = () => DateTime.now();

        expect(cacheIndex.isExpired('prefs:expired'), isTrue);
      });
    });

    group('removeExpiry', () {
      test('removes expiration metadata', () async {
        await cacheIndex.init();
        await cacheIndex.setExpiry('prefs:key', const Duration(hours: 1));

        await cacheIndex.removeExpiry('prefs:key');

        expect(cacheIndex.getMetadata('prefs:key'), isNull);
      });

      test('does nothing for non-existent key', () async {
        await cacheIndex.init();

        await cacheIndex.removeExpiry('prefs:missing');

        expect(cacheIndex.getMetadata('prefs:missing'), isNull);
      });
    });

    group('getExpiredEntries', () {
      test('returns empty list when no entries', () async {
        await cacheIndex.init();

        expect(cacheIndex.getExpiredEntries(), isEmpty);
      });

      test('returns only expired entries', () async {
        await cacheIndex.init();

        // Create expired entry
        final pastTime = DateTime.now().subtract(const Duration(hours: 2));
        cacheIndex.clock = () => pastTime;
        await cacheIndex.setExpiry('prefs:expired1', const Duration(hours: 1));
        await cacheIndex.setExpiry('prefs:expired2', const Duration(minutes: 30));

        // Create valid entry
        cacheIndex.clock = () => DateTime.now();
        await cacheIndex.setExpiry('prefs:valid', const Duration(hours: 1));

        final expired = cacheIndex.getExpiredEntries();

        expect(expired.length, 2);
        expect(
          expired.map((e) => e.storageKey),
          containsAll(['prefs:expired1', 'prefs:expired2']),
        );
      });
    });

    group('metadataCount', () {
      test('returns 0 when empty', () async {
        await cacheIndex.init();

        expect(cacheIndex.metadataCount, 0);
      });

      test('returns count of entries', () async {
        await cacheIndex.init();
        await cacheIndex.setExpiry('prefs:key1', const Duration(hours: 1));
        await cacheIndex.setExpiry('prefs:key2', const Duration(hours: 1));
        await cacheIndex.setExpiry('hive:box:key3', const Duration(hours: 1));

        expect(cacheIndex.metadataCount, 3);
      });
    });

    group('expiredCount', () {
      test('returns 0 when no expired entries', () async {
        await cacheIndex.init();
        await cacheIndex.setExpiry('prefs:valid', const Duration(hours: 1));

        expect(cacheIndex.expiredCount, 0);
      });

      test('returns count of expired entries', () async {
        await cacheIndex.init();

        // Create expired entries
        final pastTime = DateTime.now().subtract(const Duration(hours: 2));
        cacheIndex.clock = () => pastTime;
        await cacheIndex.setExpiry('prefs:expired1', const Duration(hours: 1));
        await cacheIndex.setExpiry('prefs:expired2', const Duration(hours: 1));

        // Create valid entry
        cacheIndex.clock = () => DateTime.now();
        await cacheIndex.setExpiry('prefs:valid', const Duration(hours: 1));

        expect(cacheIndex.expiredCount, 2);
      });
    });

    group('clear', () {
      test('clears all metadata', () async {
        await cacheIndex.init();
        await cacheIndex.setExpiry('prefs:key1', const Duration(hours: 1));
        await cacheIndex.setExpiry('prefs:key2', const Duration(hours: 1));

        await cacheIndex.clear();

        expect(cacheIndex.metadataCount, 0);
      });
    });
  });
}
