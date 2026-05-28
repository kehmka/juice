import 'dart:typed_data';

import 'package:juice_storage/juice_storage.dart';
import 'package:mocktail/mocktail.dart';

/// Mock [StorageBloc] used across the network test suites.
class MockStorageBloc extends Mock implements StorageBloc {}

/// Create a [MockStorageBloc] backed by an in-memory map.
///
/// Unlike a plain mock that always returns `null`, this lets `CacheManager`
/// (and therefore the cache policies) work end-to-end: writes are persisted to
/// [backing] and reads return what was written. TTL is intentionally ignored —
/// expiry lives inside the serialized `WireCacheRecord`, so expiry tests work
/// by seeding records with a past `expiresAt`.
MockStorageBloc createStatefulStorageBloc([Map<String, Uint8List>? backing]) {
  final store = backing ?? <String, Uint8List>{};
  final mock = MockStorageBloc();

  // CacheManager writes Uint8List, so the generic call resolves to
  // hiveWrite<Uint8List>. mocktail matches the type argument, so the stub must
  // be registered with the same one (and a matching fallback value).
  registerFallbackValue(Uint8List(0));

  when(() => mock.hiveOpenBox(any())).thenAnswer((_) async {});

  when(() => mock.hiveWrite<Uint8List>(any(), any(), any(),
      ttl: any(named: 'ttl'))).thenAnswer((inv) async {
    final key = inv.positionalArguments[1] as String;
    final value = inv.positionalArguments[2];
    if (value is Uint8List) store[key] = value;
  });

  when(() => mock.hiveRead<Uint8List>(any(), any())).thenAnswer((inv) async {
    final key = inv.positionalArguments[1] as String;
    return store[key];
  });

  when(() => mock.hiveDelete(any(), any())).thenAnswer((inv) async {
    final key = inv.positionalArguments[1] as String;
    store.remove(key);
  });

  when(() => mock.hiveKeys(any())).thenAnswer((_) async => store.keys.toList());

  return mock;
}
