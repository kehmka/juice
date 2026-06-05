import 'mutation.dart';

/// Durable persistence seam for the outbox.
///
/// The flush engine depends only on this interface. Default:
/// `StorageSyncStore` (juice_storage-backed). `InMemorySyncStore` is for tests
/// and demos — **not** durable, so never use it as a real outbox.
///
/// Every method that fails must throw (surfaced as a `StorageSyncError` by
/// callers) — a silent storage failure would lose user writes.
abstract class SyncStore {
  /// Persist (insert or update) a mutation.
  Future<void> put(Mutation mutation);

  /// Remove a mutation by id.
  Future<void> delete(String id);

  /// Load every persisted mutation, **sorted by `seq` ascending** (durable
  /// FIFO across restarts).
  Future<List<Mutation>> loadAll();

  /// A monotonically increasing, **persisted** sequence number.
  Future<int> nextSeq();

  /// Release resources.
  Future<void> dispose();
}

/// In-memory [SyncStore] for tests and demos. Not durable.
class InMemorySyncStore implements SyncStore {
  final Map<String, Mutation> _items = {};
  int _seq = 0;

  /// Pre-seed (e.g. to simulate a queue surviving a restart in tests).
  InMemorySyncStore([List<Mutation> seed = const []]) {
    for (final m in seed) {
      _items[m.id] = m;
      if (m.seq >= _seq) _seq = m.seq + 1;
    }
  }

  @override
  Future<void> put(Mutation mutation) async => _items[mutation.id] = mutation;

  @override
  Future<void> delete(String id) async => _items.remove(id);

  @override
  Future<List<Mutation>> loadAll() async {
    final list = _items.values.toList()..sort((a, b) => a.seq.compareTo(b.seq));
    return list;
  }

  @override
  Future<int> nextSeq() async => _seq++;

  @override
  Future<void> dispose() async {}
}
