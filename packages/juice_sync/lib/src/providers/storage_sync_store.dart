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

  @override
  Future<void> put(Mutation mutation) async {
    try {
      await _storage.hiveWrite(box, mutation.id, jsonEncode(mutation.toJson()));
    } catch (e) {
      throw StorageSyncError('put(${mutation.id}) failed', cause: e);
    }
  }

  @override
  Future<void> delete(String id) async {
    try {
      await _storage.hiveDelete(box, id);
    } catch (e) {
      throw StorageSyncError('delete($id) failed', cause: e);
    }
  }

  @override
  Future<List<Mutation>> loadAll() async {
    try {
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
