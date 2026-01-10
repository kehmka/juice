import 'package:flutter_test/flutter_test.dart';
import 'package:juice_storage/src/cache/cache_metadata.dart';

void main() {
  group('CacheMetadata', () {
    group('constructor', () {
      test('creates metadata with provided values', () {
        final createdAt = DateTime(2024, 1, 1);
        final expiresAt = DateTime(2024, 1, 2);

        final meta = CacheMetadata(
          storageKey: 'test:key',
          createdAt: createdAt,
          expiresAt: expiresAt,
        );

        expect(meta.storageKey, 'test:key');
        expect(meta.createdAt, createdAt);
        expect(meta.expiresAt, expiresAt);
      });
    });

    group('withTTL factory', () {
      test('creates metadata with TTL', () {
        final now = DateTime(2024, 1, 1, 12, 0, 0);
        const ttl = Duration(hours: 2);

        final meta = CacheMetadata.withTTL(
          storageKey: 'test:key',
          ttl: ttl,
          now: now,
        );

        expect(meta.storageKey, 'test:key');
        expect(meta.createdAt, now);
        expect(meta.expiresAt, DateTime(2024, 1, 1, 14, 0, 0));
      });

      test('handles minute TTL', () {
        final now = DateTime(2024, 1, 1, 12, 0, 0);
        const ttl = Duration(minutes: 30);

        final meta = CacheMetadata.withTTL(
          storageKey: 'test:key',
          ttl: ttl,
          now: now,
        );

        expect(meta.expiresAt, DateTime(2024, 1, 1, 12, 30, 0));
      });

      test('handles day TTL', () {
        final now = DateTime(2024, 1, 1, 12, 0, 0);
        const ttl = Duration(days: 7);

        final meta = CacheMetadata.withTTL(
          storageKey: 'test:key',
          ttl: ttl,
          now: now,
        );

        expect(meta.expiresAt, DateTime(2024, 1, 8, 12, 0, 0));
      });

      test('uses current time when now is not provided', () {
        const ttl = Duration(hours: 1);
        final before = DateTime.now();

        final meta = CacheMetadata.withTTL(
          storageKey: 'test:key',
          ttl: ttl,
        );

        final after = DateTime.now();

        expect(
            meta.createdAt.isAfter(before.subtract(const Duration(seconds: 1))),
            isTrue);
        expect(meta.createdAt.isBefore(after.add(const Duration(seconds: 1))),
            isTrue);
      });
    });

    group('isExpired getter', () {
      test('returns true when expired', () {
        // Create a metadata that expired in the past
        final meta = CacheMetadata(
          storageKey: 'test:key',
          createdAt: DateTime.now().subtract(const Duration(hours: 2)),
          expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
        );

        expect(meta.isExpired, isTrue);
      });

      test('returns false when not expired', () {
        // Create a metadata that expires in the future
        final meta = CacheMetadata(
          storageKey: 'test:key',
          createdAt: DateTime.now(),
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        );

        expect(meta.isExpired, isFalse);
      });
    });

    group('timeRemaining getter', () {
      test('returns positive duration when not expired', () {
        final meta = CacheMetadata(
          storageKey: 'test:key',
          createdAt: DateTime.now(),
          expiresAt: DateTime.now().add(const Duration(hours: 2)),
        );

        // Should be roughly 2 hours (within a few seconds tolerance)
        expect(meta.timeRemaining.inMinutes, greaterThanOrEqualTo(119));
        expect(meta.timeRemaining.inMinutes, lessThanOrEqualTo(120));
      });

      test('returns negative duration when expired', () {
        final meta = CacheMetadata(
          storageKey: 'test:key',
          createdAt: DateTime.now().subtract(const Duration(hours: 3)),
          expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
        );

        expect(meta.timeRemaining.isNegative, isTrue);
      });
    });
  });
}
