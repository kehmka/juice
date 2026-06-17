import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
// A VM test can't use StorageBloc.initialize() (it calls Hive.initFlutter,
// which needs a platform channel), so we construct the bloc with a pre-init'd
// CacheIndex and let the store open its boxes — the same pattern juice_storage's
// own bloc test uses.
import 'package:juice_storage/juice_storage.dart';
import 'package:juice_sync/juice_sync.dart';

/// Regression: `StorageSyncStore` must open its own Hive boxes.
///
/// The app can't declare them in `StorageConfig.hiveBoxesToOpen` — the meta box
/// name is private to the store — so before this fix, an app that didn't
/// (couldn't) pre-open the outbox hit `boxNotOpen` on `loadAll` at startup
/// (SyncBloc init → SyncStatus.error). The StorageBloc here is created with a
/// default config (NO hiveBoxesToOpen), reproducing that exact setup — so every
/// op below would have thrown before the fix.
void main() {
  late Directory tempDir;
  late StorageSyncStore store;
  late StorageBloc storage;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('sync_store_test_');
    Hive.init(tempDir.path);
    final cacheIndex = CacheIndex();
    await cacheIndex.init();
    // Default config: deliberately does NOT open the sync boxes (reproduces an
    // app that can't, since the meta box name is private to the store).
    storage = StorageBloc(config: const StorageConfig(), cacheIndex: cacheIndex);
    store = StorageSyncStore(storage);
  });

  tearDownAll(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Mutation mut(String id, int seq) => Mutation(
        id: id,
        seq: seq,
        type: 'createCapture',
        payload: const {'x': 1},
        createdAt: DateTime(2026, 6, 16),
      );

  test('write + read on never-pre-opened boxes (was boxNotOpen)', () async {
    // put exercises the outbox; before the fix _ensureOpen didn't exist and
    // this threw StorageSyncError(boxNotOpen).
    await store.put(mut('w1', 1));
    expect((await store.loadAll()).map((m) => m.id), contains('w1'));
  });

  test('delete removes the mutation', () async {
    await store.put(mut('d1', 5));
    expect((await store.loadAll()).map((m) => m.id), contains('d1'));
    await store.delete('d1');
    expect((await store.loadAll()).map((m) => m.id), isNot(contains('d1')));
  });

  test('nextSeq is monotonic (private meta box opened by the store)', () async {
    final a = await store.nextSeq();
    final b = await store.nextSeq();
    expect(b, greaterThan(a));
  });

  test('loadAll returns mutations in seq order', () async {
    await store.put(mut('fifo_hi', 9002));
    await store.put(mut('fifo_lo', 9001));
    final ids = (await store.loadAll()).map((m) => m.id).toList();
    expect(ids.indexOf('fifo_lo'), lessThan(ids.indexOf('fifo_hi')));
  });

  test('a fresh store over the same storage reloads persisted data', () async {
    await store.put(mut('persist1', 7000));
    final reopened = StorageSyncStore(storage); // simulates restart wiring
    expect((await reopened.loadAll()).map((m) => m.id), contains('persist1'));
  });

  test('StorageSyncError surfaces its cause (loud, not opaque)', () {
    final e = StorageSyncError('put failed', cause: StateError('disk full'));
    expect(e.toString(), contains('put failed'));
    expect(e.toString(), contains('disk full'));
  });
}
