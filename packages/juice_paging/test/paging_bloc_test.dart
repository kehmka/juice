
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_paging/juice_paging.dart';

/// Sentinel so "no failure configured" can't collide with a null cursor.
final _noFail = Object();

/// A fake paged backend: pages of [pageSize] up to [total]; cursor = next offset.
class FakeBackend {
  int total;
  final int pageSize;
  int calls = 0;
  Object? failNextCursor; // when the cursor matches this, throw once
  bool _failed = false;

  FakeBackend({this.total = 25, this.pageSize = 10}) : failNextCursor = _noFail;

  Future<PageResult<int>> fetch(Object? cursor) async {
    calls++;
    final offset = (cursor as int?) ?? 0;
    if (failNextCursor == cursor && !_failed) {
      _failed = true;
      throw StateError('boom at $cursor');
    }
    final end = (offset + pageSize).clamp(0, total);
    final items = [for (var i = offset; i < end; i++) i];
    final next = end < total ? end : null;
    return PageResult(items, nextCursor: next);
  }
}

void main() {
  Future<void> settle([int ms = 20]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  group('PagingState model', () {
    test('defaults', () {
      const s = PagingState<int>();
      expect(s.items, isEmpty);
      expect(s.status, PagingStatus.initial);
    });
  });

  group('Load + paginate', () {
    test('loads the first page on init', () async {
      final be = FakeBackend(total: 25);
      final bloc = PagingBloc<int>.withConfig(PagingConfig(fetcher: be.fetch));
      await settle();

      expect(bloc.state.items, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
      expect(bloc.state.status, PagingStatus.loaded);
      expect(bloc.state.hasMore, isTrue);
      await bloc.close();
    });

    test('loadMore appends pages until the end', () async {
      final be = FakeBackend(total: 25);
      final bloc = PagingBloc<int>.withConfig(PagingConfig(fetcher: be.fetch));
      await settle();

      bloc.loadMore();
      await settle();
      expect(bloc.state.items.length, 20);

      bloc.loadMore();
      await settle();
      expect(bloc.state.items.length, 25);
      expect(bloc.state.status, PagingStatus.end);
      expect(bloc.state.hasMore, isFalse);

      // loadMore past the end is a no-op.
      final callsBefore = be.calls;
      bloc.loadMore();
      await settle();
      expect(be.calls, callsBefore);
      await bloc.close();
    });

    test('concurrent loadMore is guarded (one fetch)', () async {
      final be = FakeBackend(total: 100);
      final bloc = PagingBloc<int>.withConfig(PagingConfig(fetcher: be.fetch));
      await settle();

      final callsBefore = be.calls;
      bloc.loadMore();
      bloc.loadMore(); // should be ignored while the first is in flight
      bloc.loadMore();
      await settle();

      expect(be.calls, callsBefore + 1); // only one extra page fetched
      expect(bloc.state.items.length, 20);
      await bloc.close();
    });
  });

  group('Refresh', () {
    test('refresh reloads from the first page', () async {
      final be = FakeBackend(total: 25);
      final bloc = PagingBloc<int>.withConfig(PagingConfig(fetcher: be.fetch));
      await settle();
      bloc.loadMore();
      await settle();
      expect(bloc.state.items.length, 20);

      be.total = 5; // backend shrank
      bloc.refresh();
      await settle();
      expect(bloc.state.items, [0, 1, 2, 3, 4]);
      expect(bloc.state.status, PagingStatus.end);
      await bloc.close();
    });
  });

  group('Errors', () {
    test('first-page error → error status, retry recovers', () async {
      final be = FakeBackend(total: 25)..failNextCursor = null; // first page fails
      final bloc = PagingBloc<int>.withConfig(PagingConfig(fetcher: be.fetch));
      await settle();

      expect(bloc.state.status, PagingStatus.error);
      expect(bloc.state.error, contains('boom'));
      expect(bloc.state.items, isEmpty);

      bloc.retry();
      await settle();
      expect(bloc.state.items.length, 10);
      expect(bloc.state.status, PagingStatus.loaded);
      await bloc.close();
    });

    test('loadMore error keeps items; retry resumes', () async {
      final be = FakeBackend(total: 25)..failNextCursor = 10; // 2nd page fails once
      final bloc = PagingBloc<int>.withConfig(PagingConfig(fetcher: be.fetch));
      await settle();
      expect(bloc.state.items.length, 10);

      bloc.loadMore();
      await settle();
      expect(bloc.state.status, PagingStatus.error);
      expect(bloc.state.items.length, 10); // kept

      bloc.retry();
      await settle();
      expect(bloc.state.items.length, 20);
      expect(bloc.state.status, PagingStatus.loaded);
      await bloc.close();
    });
  });
}
