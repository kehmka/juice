---
card_schema: "1.0"
package: juice_paging
version: 0.1.0
requires:
  juice: ">=1.4.0"
updated: 2026-06-09
---

# juice_paging — AI card

> Generic paged / infinite-scroll list bloc: fetch pages through a cursor-based
> seam, append on `loadMore`, replace on `refresh`, with an in-flight guard and
> error recovery. Read repo `AGENTS.md` for the Juice mental model + gotchas.

## Purpose

**Owns:** the loaded items + load status/cursor.
**Does NOT own:** the transport (a `PageFetcher` seam) or the list UI.

## When to use

Any cursor/offset/token-paginated list or infinite-scroll feed where you want
append-on-scroll, pull-to-refresh, and retry without hand-rolling the load
state machine. For a single mutation queue use `juice_sync`; for caching reads
use `juice_network`.

## Install

```yaml
dependencies:
  juice_paging: ^0.1.0
```

## Construct

The `fetcher` seam is **required**. `withConfig` applies config and triggers the
first load (unless `loadOnInit: false`):

```dart
final feed = PagingBloc<Post>.withConfig(PagingConfig<Post>(
  fetcher: (cursor) async {
    final page = await api.posts(after: cursor as String?);
    return PageResult(page.items, nextCursor: page.next);   // null next ⇒ end
  },
  loadOnInit: true,
));
// in a scroll listener: feed.loadMore();
```

## Seams

```dart
// cursor is null for the first page, else the previous PageResult.nextCursor.
// Throw to surface a load error (items are preserved). REQUIRED.
typedef PageFetcher<T> = Future<PageResult<T>> Function(Object? cursor);

class PageResult<T> {
  final List<T> items;
  final Object? nextCursor;   // opaque: offset / token / timestamp; null ⇒ end
  bool get hasMore;           // nextCursor != null
}
```

## API

```dart
void refresh();               // reload from first page, replacing items
void loadMore();              // append next page (guarded)
void retry();                 // retry whichever load failed
bool get isLoading;           // in-flight guard
PageFetcher<T> get fetcher;
```

## Events

| Event | Effect |
|---|---|
| `InitializePagingEvent` | sends `RefreshPageEvent` if `loadOnInit` |
| `RefreshPageEvent` | `fetch(null)`, replace items; existing items stay visible during load |
| `LoadMoreEvent` | `fetch(nextCursor)`, append; **no-op** if loading, at `end`, or status still `initial` |
| `RetryPageEvent` | re-dispatch refresh (empty list) or loadMore (non-empty) |

## State

```dart
enum PagingStatus { initial, loadingFirst, loaded, loadingMore, end, error }

class PagingState<T> {        // BlocState
  List<T> items; PagingStatus status; Object? nextCursor; String? error;
  bool get isLoadingFirst; bool get isLoadingMore;
  bool get hasMore;           // status != end && status != loadingFirst
  bool get isEmpty;           // items.isEmpty
}
```

## Rebuild groups

| Group | Emitted when |
|---|---|
| `PagingGroups.items` → `paging:items` | the item list changed (page appended/replaced) |
| `PagingGroups.status` → `paging:status` | load status / error changed (spinners + retry) |

`PagingGroups.all = {items, status}`.

## Concurrency

Use cases run with the default `concurrent` mode; overlap is prevented by a
bloc-side boolean guard `_loading` (`isLoading` / `beginLoad` / `endLoad`).
`refresh` and `loadMore` both early-return while a load is in flight, so a
scroll listener firing `loadMore()` repeatedly issues exactly one fetch.

## Recipes

```dart
// 1. Offset-paginated fetcher (encode the offset in the cursor)
PagingBloc<Item>.withConfig(PagingConfig<Item>(fetcher: (cursor) async {
  final offset = cursor as int? ?? 0;
  final batch = await api.list(offset: offset, limit: 20);
  return PageResult(batch, nextCursor: batch.length < 20 ? null : offset + 20);
}));

// 2. Infinite scroll trigger
controller.addListener(() {
  if (controller.position.extentAfter < 400) feed.loadMore();  // guard handles spam
});

// 3. List + footer bound to separate groups (minimal rebuilds)
class FeedList extends StatelessJuiceWidget<PagingBloc<Post>> {
  FeedList({super.key}) : super(groups: {PagingGroups.items});
  @override Widget onBuild(BuildContext c, StreamStatus s) =>
      ListView(children: [for (final p in bloc.state.items) PostTile(p)]);
}
class FeedFooter extends StatelessJuiceWidget<PagingBloc<Post>> {
  FeedFooter({super.key}) : super(groups: {PagingGroups.status});
  @override Widget onBuild(BuildContext c, StreamStatus s) {
    if (bloc.state.isLoadingMore) return const CircularProgressIndicator();
    if (bloc.state.status == PagingStatus.error) {
      return TextButton(onPressed: bloc.retry, child: const Text('Retry'));
    }
    return const SizedBox.shrink();
  }
}
```

## Testing

Headless — a fake offset backend, drive the convenience API, `settle()`:

```dart
PageResult<int> Function(Object?) fakeBackend({int total = 50, int size = 20}) =>
    (cursor) async {
      final offset = cursor as int? ?? 0;
      final slice = List.generate(
          (total - offset).clamp(0, size), (i) => offset + i);
      return PageResult(slice, nextCursor: offset + size >= total ? null : offset + size);
    };
final bloc = PagingBloc<int>.withConfig(PagingConfig(fetcher: fakeBackend()));
await settle();                       // first page loaded
expect(bloc.state.items.length, 20);
bloc.loadMore(); bloc.loadMore();     // spam → guard issues one fetch
await settle();
expect(bloc.state.items.length, 40);
```

## Failure modes

- A `fetcher` throw → `emitFailure` with `status: error`, `error: e.toString()`;
  **items and `nextCursor` are preserved** so `retry()` resumes from the same
  point. Refresh failure leaves whatever items were already shown.
- `loadMore` while `status == initial` is a no-op — refresh must run first.
- The guard is released in a `finally`, so an exception can't wedge `isLoading`.

## Anti-patterns

- ❌ Calling `loadMore()` before a refresh has populated the cursor — it no-ops
  (status `initial`). Let `loadOnInit`/`refresh` seed page one.
- ❌ Making event types generic — events are **non-generic** so Juice's
  type-keyed dispatch matches; only the use cases and state carry `<T>`.
- ❌ Treating `nextCursor` as page-number-only — it's opaque; carry a token or
  timestamp if that's what the backend uses.
- ❌ Adding your own in-flight flag — `isLoading` already serializes loads.

## Invariants

- **Single in-flight load:** `refresh`/`loadMore` are mutually exclusive via the
  `_loading` guard.
- **End is sticky until refresh:** once `status == end`, `loadMore` no-ops; only
  `refresh` re-opens the list.
- **Error preserves items + cursor** — retry resumes, never restarts mid-list.

## See also

`SPEC.md` (behavior/boundary) · `README.md` (narrative) · repo `AGENTS.md` (framework).
