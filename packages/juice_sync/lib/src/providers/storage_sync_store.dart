import 'dart:convert';

import 'package:juice_storage/juice_storage.dart';

import '../mutation.dart';
import '../sync_errors.dart';
import '../sync_store.dart';

/// Durable [SyncStore] backed by `juice_storage` (Hive box). This is the only
/// file that references `StorageBloc` — the flush engine sees only [SyncStore].
///
/// Mutations are keyed by id (so `delete(id)` is trivial); ordering is by the
/// persisted `seq` field, sorted on load. A monotonic sequence counter is
/// persisted separately so FIFO order survives restarts.
class StorageSyncStore implements SyncStore {
  final StorageBloc _storage;
  final String box;
  final String _metaBox;
  static const _seqKey = 'seq';

  StorageSyncStore(
    StorageBloc storage, {
    this.box = 'juice_sync_outbox',
  })  : _storage = storage,
        _metaBox = 'juice_sync_meta';

  bool _opened = false;

  /// Open the store's two boxes before first use. The store owns both names
  /// (the meta box is private), so the app *can't* pre-declare them in
  /// `StorageConfig.hiveBoxesToOpen` — the store must open them itself, or
  /// `loadAll` fails with `boxNotOpen` at startup. `hiveOpenBox` is idempotent
  /// (the adapter factory returns the already-open box), so this is cheap to
  /// guard on every call and self-heals if a box was closed.
  Future<void> _ensureOpen() async {
    if (_opened) return;
    await _storage.hiveOpenBox(box);
    await _storage.hiveOpenBox(_metaBox);
    _opened = true;
  }

  @override
  Future<void> put(Mutation mutation) async {
    try {
      await _ensureOpen();
      await _storage.hiveWrite(box, mutation.id, jsonEncode(mutation.toJson()));
    } catch (e) {
      throw StorageSyncError('put(${mutation.id}) failed', cause: e);
    }
  }

  @override
  Future<void> delete(String id) async {
    try {
      await _ensureOpen();
      await _storage.hiveDelete(box, id);
    } catch (e) {
      throw StorageSyncError('delete($id) failed', cause: e);
    }
  }

  @override
  Future<List<Mutation>> loadAll() async {
    try {
      await _ensureOpen();
      final keys = await _storage.hiveKeys(box);
      final out = <Mutation>[];
      for (final k in keys) {
        final raw = await _storage.hiveRead<String>(box, k);
        if (raw == null) continue;
        out.add(Mutation.fromJson(
            (jsonDecode(raw) as Map).cast<String, Object?>()));
      }
      out.sort((a, b) => a.seq.compareTo(b.seq)); // durable FIFO order
      return out;
    } catch (e) {
      throw StorageSyncError('loadAll failed', cause: e);
    }
  }

  @override
  Future<int> nextSeq() async {
    try {
      await _ensureOpen();
      final current = await _storage.hiveRead<int>(_metaBox, _seqKey) ?? 0;
      final next = current + 1;
      await _storage.hiveWrite(_metaBox, _seqKey, next);
      return next;
    } catch (e) {
      throw StorageSyncError('nextSeq failed', cause: e);
    }
  }

  @override
  Future<void> dispose() async {}
}
