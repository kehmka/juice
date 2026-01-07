import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_storage/src/adapters/secure_adapter.dart';
import 'package:mocktail/mocktail.dart';

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  group('SecureAdapter', () {
    late MockFlutterSecureStorage mockStorage;
    late SecureAdapter adapter;

    setUp(() {
      mockStorage = MockFlutterSecureStorage();
      adapter = SecureAdapter(storage: mockStorage);
    });

    group('read', () {
      test('reads value by key', () async {
        when(() => mockStorage.read(key: 'secret'))
            .thenAnswer((_) async => 'secret_value');

        final result = await adapter.read('secret');

        expect(result, 'secret_value');
        verify(() => mockStorage.read(key: 'secret')).called(1);
      });

      test('returns null when key not found', () async {
        when(() => mockStorage.read(key: 'missing'))
            .thenAnswer((_) async => null);

        final result = await adapter.read('missing');

        expect(result, isNull);
      });
    });

    group('write', () {
      test('writes value by key', () async {
        when(() => mockStorage.write(key: 'secret', value: 'secret_value'))
            .thenAnswer((_) async {});

        await adapter.write('secret', 'secret_value');

        verify(() => mockStorage.write(key: 'secret', value: 'secret_value'))
            .called(1);
      });
    });

    group('delete', () {
      test('deletes key', () async {
        when(() => mockStorage.delete(key: 'secret')).thenAnswer((_) async {});

        await adapter.delete('secret');

        verify(() => mockStorage.delete(key: 'secret')).called(1);
      });
    });

    group('clear', () {
      test('deletes all entries', () async {
        when(() => mockStorage.deleteAll()).thenAnswer((_) async {});

        await adapter.clear();

        verify(() => mockStorage.deleteAll()).called(1);
      });
    });

    group('containsKey', () {
      test('returns true when key exists', () async {
        when(() => mockStorage.containsKey(key: 'exists'))
            .thenAnswer((_) async => true);

        final result = await adapter.containsKey('exists');

        expect(result, isTrue);
      });

      test('returns false when key does not exist', () async {
        when(() => mockStorage.containsKey(key: 'missing'))
            .thenAnswer((_) async => false);

        final result = await adapter.containsKey('missing');

        expect(result, isFalse);
      });
    });

    group('keys', () {
      test('returns all keys', () async {
        when(() => mockStorage.readAll()).thenAnswer((_) async => {
              'key1': 'value1',
              'key2': 'value2',
              'key3': 'value3',
            });

        final result = await adapter.keys();

        expect(result.toList(), ['key1', 'key2', 'key3']);
      });

      test('returns empty when no keys', () async {
        when(() => mockStorage.readAll()).thenAnswer((_) async => {});

        final result = await adapter.keys();

        expect(result, isEmpty);
      });
    });
  });

  group('SecureAdapterFactory', () {
    setUp(() {
      SecureAdapterFactory.reset();
    });

    test('instance returns null before init', () {
      expect(SecureAdapterFactory.instance, isNull);
    });

    test('reset clears the adapter', () {
      // Can't fully test init without platform, but can test reset
      SecureAdapterFactory.reset();
      expect(SecureAdapterFactory.instance, isNull);
    });
  });
}
