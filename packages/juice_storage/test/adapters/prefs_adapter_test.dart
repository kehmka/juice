import 'package:flutter_test/flutter_test.dart';
import 'package:juice_storage/src/adapters/prefs_adapter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockSharedPreferences extends Mock implements SharedPreferences {}

void main() {
  group('PrefsAdapter', () {
    late MockSharedPreferences mockPrefs;
    late PrefsAdapter adapter;
    const keyPrefix = 'test_';

    setUp(() {
      mockPrefs = MockSharedPreferences();
      adapter = PrefsAdapter(prefs: mockPrefs, keyPrefix: keyPrefix);
    });

    group('read', () {
      test('reads value with prefixed key', () async {
        when(() => mockPrefs.get('test_myKey')).thenReturn('myValue');

        final result = await adapter.read('myKey');

        expect(result, 'myValue');
        verify(() => mockPrefs.get('test_myKey')).called(1);
      });

      test('returns null when key not found', () async {
        when(() => mockPrefs.get('test_missing')).thenReturn(null);

        final result = await adapter.read('missing');

        expect(result, isNull);
      });

      test('reads different types', () async {
        when(() => mockPrefs.get('test_string')).thenReturn('hello');
        when(() => mockPrefs.get('test_int')).thenReturn(42);
        when(() => mockPrefs.get('test_double')).thenReturn(3.14);
        when(() => mockPrefs.get('test_bool')).thenReturn(true);
        when(() => mockPrefs.get('test_list')).thenReturn(['a', 'b']);

        expect(await adapter.read('string'), 'hello');
        expect(await adapter.read('int'), 42);
        expect(await adapter.read('double'), 3.14);
        expect(await adapter.read('bool'), true);
        expect(await adapter.read('list'), ['a', 'b']);
      });
    });

    group('write', () {
      test('writes String with prefixed key', () async {
        when(() => mockPrefs.setString('test_key', 'value'))
            .thenAnswer((_) async => true);

        await adapter.write('key', 'value');

        verify(() => mockPrefs.setString('test_key', 'value')).called(1);
      });

      test('writes int with prefixed key', () async {
        when(() => mockPrefs.setInt('test_key', 42))
            .thenAnswer((_) async => true);

        await adapter.write('key', 42);

        verify(() => mockPrefs.setInt('test_key', 42)).called(1);
      });

      test('writes double with prefixed key', () async {
        when(() => mockPrefs.setDouble('test_key', 3.14))
            .thenAnswer((_) async => true);

        await adapter.write('key', 3.14);

        verify(() => mockPrefs.setDouble('test_key', 3.14)).called(1);
      });

      test('writes bool with prefixed key', () async {
        when(() => mockPrefs.setBool('test_key', true))
            .thenAnswer((_) async => true);

        await adapter.write('key', true);

        verify(() => mockPrefs.setBool('test_key', true)).called(1);
      });

      test('writes List<String> with prefixed key', () async {
        when(() => mockPrefs.setStringList('test_key', ['a', 'b']))
            .thenAnswer((_) async => true);

        await adapter.write('key', ['a', 'b']);

        verify(() => mockPrefs.setStringList('test_key', ['a', 'b'])).called(1);
      });

      test('throws for unsupported type', () async {
        expect(
          () => adapter.write('key', DateTime.now()),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('delete', () {
      test('removes key with prefix', () async {
        when(() => mockPrefs.remove('test_key')).thenAnswer((_) async => true);

        await adapter.delete('key');

        verify(() => mockPrefs.remove('test_key')).called(1);
      });
    });

    group('clear', () {
      test('only clears keys with matching prefix', () async {
        when(() => mockPrefs.getKeys()).thenReturn({
          'test_key1',
          'test_key2',
          'other_key',
          'another_key',
        });
        when(() => mockPrefs.remove(any())).thenAnswer((_) async => true);

        await adapter.clear();

        verify(() => mockPrefs.remove('test_key1')).called(1);
        verify(() => mockPrefs.remove('test_key2')).called(1);
        verifyNever(() => mockPrefs.remove('other_key'));
        verifyNever(() => mockPrefs.remove('another_key'));
      });
    });

    group('containsKey', () {
      test('checks with prefixed key', () async {
        when(() => mockPrefs.containsKey('test_exists')).thenReturn(true);
        when(() => mockPrefs.containsKey('test_missing')).thenReturn(false);

        expect(await adapter.containsKey('exists'), isTrue);
        expect(await adapter.containsKey('missing'), isFalse);
      });
    });

    group('keys', () {
      test('returns logical keys without prefix', () async {
        when(() => mockPrefs.getKeys()).thenReturn({
          'test_key1',
          'test_key2',
          'other_key',
        });

        final result = await adapter.keys();

        expect(result.toList(), ['key1', 'key2']);
      });
    });

    group('keyPrefix', () {
      test('returns the configured prefix', () {
        expect(adapter.keyPrefix, 'test_');
      });
    });

    group('reload', () {
      test('reloads preferences', () async {
        when(() => mockPrefs.reload()).thenAnswer((_) async {});

        await adapter.reload();

        verify(() => mockPrefs.reload()).called(1);
      });
    });
  });

  group('PrefsAdapterFactory', () {
    setUp(() {
      PrefsAdapterFactory.reset();
    });

    test('init throws when prefs is null', () {
      expect(
        () => PrefsAdapterFactory.init(keyPrefix: 'test_'),
        throwsA(isA<StateError>()),
      );
    });

    test('init creates adapter with prefs', () {
      final mockPrefs = MockSharedPreferences();

      final adapter = PrefsAdapterFactory.init(
        prefs: mockPrefs,
        keyPrefix: 'test_',
      );

      expect(adapter, isNotNull);
      expect(PrefsAdapterFactory.instance, adapter);
    });

    test('init returns existing adapter on subsequent calls', () {
      final mockPrefs = MockSharedPreferences();

      final adapter1 = PrefsAdapterFactory.init(
        prefs: mockPrefs,
        keyPrefix: 'test_',
      );
      final adapter2 = PrefsAdapterFactory.init(
        prefs: mockPrefs,
        keyPrefix: 'other_',
      );

      expect(adapter1, same(adapter2));
    });

    test('reset clears the adapter', () {
      final mockPrefs = MockSharedPreferences();
      PrefsAdapterFactory.init(prefs: mockPrefs, keyPrefix: 'test_');

      PrefsAdapterFactory.reset();

      expect(PrefsAdapterFactory.instance, isNull);
    });
  });
}
