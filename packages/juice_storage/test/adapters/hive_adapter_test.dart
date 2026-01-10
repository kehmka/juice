import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:juice_storage/src/adapters/hive_adapter.dart';
import 'package:mocktail/mocktail.dart';

class MockBox<T> extends Mock implements Box<T> {}

class MockLazyBox<T> extends Mock implements LazyBox<T> {}

void main() {
  group('HiveAdapter', () {
    late MockBox<String> mockBox;
    late HiveAdapter<String> adapter;

    setUp(() {
      mockBox = MockBox<String>();
      adapter = HiveAdapter<String>(mockBox);
    });

    group('read', () {
      test('returns value from regular box', () async {
        when(() => mockBox.get('key')).thenReturn('value');

        final result = await adapter.read('key');

        expect(result, 'value');
        verify(() => mockBox.get('key')).called(1);
      });

      test('returns null when key not found', () async {
        when(() => mockBox.get('missing')).thenReturn(null);

        final result = await adapter.read('missing');

        expect(result, isNull);
      });
    });

    group('read from lazy box', () {
      late MockLazyBox<String> mockLazyBox;
      late HiveAdapter<String> lazyAdapter;

      setUp(() {
        mockLazyBox = MockLazyBox<String>();
        lazyAdapter = HiveAdapter<String>(mockLazyBox);
      });

      test('returns value from lazy box', () async {
        when(() => mockLazyBox.get('key'))
            .thenAnswer((_) async => 'lazy_value');

        final result = await lazyAdapter.read('key');

        expect(result, 'lazy_value');
        verify(() => mockLazyBox.get('key')).called(1);
      });

      test('isLazy returns true for lazy box', () {
        expect(lazyAdapter.isLazy, isTrue);
      });
    });

    group('write', () {
      test('puts value in box', () async {
        when(() => mockBox.put('key', 'value')).thenAnswer((_) async {});

        await adapter.write('key', 'value');

        verify(() => mockBox.put('key', 'value')).called(1);
      });
    });

    group('delete', () {
      test('deletes key from box', () async {
        when(() => mockBox.delete('key')).thenAnswer((_) async {});

        await adapter.delete('key');

        verify(() => mockBox.delete('key')).called(1);
      });
    });

    group('clear', () {
      test('clears all entries', () async {
        when(() => mockBox.clear()).thenAnswer((_) async => 5);

        await adapter.clear();

        verify(() => mockBox.clear()).called(1);
      });
    });

    group('containsKey', () {
      test('returns true when key exists', () async {
        when(() => mockBox.containsKey('key')).thenReturn(true);

        final result = await adapter.containsKey('key');

        expect(result, isTrue);
      });

      test('returns false when key does not exist', () async {
        when(() => mockBox.containsKey('missing')).thenReturn(false);

        final result = await adapter.containsKey('missing');

        expect(result, isFalse);
      });
    });

    group('keys', () {
      test('returns all keys', () async {
        when(() => mockBox.keys).thenReturn(['key1', 'key2', 'key3']);

        final result = await adapter.keys();

        expect(result, ['key1', 'key2', 'key3']);
      });
    });

    group('properties', () {
      test('boxName returns box name', () {
        when(() => mockBox.name).thenReturn('testBox');

        expect(adapter.boxName, 'testBox');
      });

      test('length returns entry count', () {
        when(() => mockBox.length).thenReturn(42);

        expect(adapter.length, 42);
      });

      test('isOpen returns box status', () {
        when(() => mockBox.isOpen).thenReturn(true);

        expect(adapter.isOpen, isTrue);
      });

      test('isLazy returns false for regular box', () {
        expect(adapter.isLazy, isFalse);
      });
    });

    group('close', () {
      test('closes the box', () async {
        when(() => mockBox.close()).thenAnswer((_) async {});

        await adapter.close();

        verify(() => mockBox.close()).called(1);
      });
    });
  });
}
