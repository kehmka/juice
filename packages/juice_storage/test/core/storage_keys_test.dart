import 'package:flutter_test/flutter_test.dart';
import 'package:juice_storage/src/core/storage_keys.dart';

void main() {
  group('StorageKeys', () {
    group('prefs', () {
      test('generates prefs key', () {
        expect(StorageKeys.prefs('theme'), 'prefs:theme');
        expect(StorageKeys.prefs('user_settings'), 'prefs:user_settings');
      });

      test('handles empty key', () {
        expect(StorageKeys.prefs(''), 'prefs:');
      });

      test('handles special characters', () {
        expect(StorageKeys.prefs('key:with:colons'), 'prefs:key:with:colons');
      });
    });

    group('hive', () {
      test('generates hive key with box', () {
        expect(StorageKeys.hive('cache', 'user'), 'hive:cache:user');
        expect(StorageKeys.hive('settings', 'theme'), 'hive:settings:theme');
      });

      test('handles colons in key', () {
        expect(
          StorageKeys.hive('box', 'key:with:colons'),
          'hive:box:key:with:colons',
        );
      });
    });

    group('secure', () {
      test('generates secure key', () {
        expect(StorageKeys.secure('token'), 'secure:token');
        expect(StorageKeys.secure('api_key'), 'secure:api_key');
      });
    });

    group('sqlite', () {
      test('generates sqlite key', () {
        expect(StorageKeys.sqlite('users', '123'), 'sqlite:users:123');
        expect(StorageKeys.sqlite('products', 'abc'), 'sqlite:products:abc');
      });
    });

    group('parse', () {
      test('parses prefs key', () {
        final result = StorageKeys.parse('prefs:myKey');
        expect(result.backend, 'prefs');
        expect(result.parts, ['myKey']);
      });

      test('parses hive key', () {
        final result = StorageKeys.parse('hive:myBox:myKey');
        expect(result.backend, 'hive');
        expect(result.parts, ['myBox', 'myKey']);
      });

      test('parses secure key', () {
        final result = StorageKeys.parse('secure:token');
        expect(result.backend, 'secure');
        expect(result.parts, ['token']);
      });

      test('parses sqlite key', () {
        final result = StorageKeys.parse('sqlite:users:123');
        expect(result.backend, 'sqlite');
        expect(result.parts, ['users', '123']);
      });

      test('throws for invalid key without colon', () {
        expect(
          () => StorageKeys.parse('invalid'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws for empty key', () {
        expect(
          () => StorageKeys.parse(''),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws for unknown backend', () {
        expect(
          () => StorageKeys.parse('unknown:key'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws for malformed hive key', () {
        expect(
          () => StorageKeys.parse('hive:nokey'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws for malformed sqlite key', () {
        expect(
          () => StorageKeys.parse('sqlite:nopk'),
          throwsA(isA<ArgumentError>()),
        );
      });
    });
  });
}
