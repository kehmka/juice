# juice_paging Specification

> **Status:** Implemented (shipping).
> **Package:** `juice_paging`
> **Primary Bloc:** `PagingBloc<T>`

## Overview

A generic paged / infinite-scroll list bloc — fetch pages through a cursor-based
seam, append on `loadMore`, replace on `refresh`, with an in-flight guard and
error recovery.

## Domain boundary

- **Owns:** the loaded items + load status/cursor.
- **Does NOT own:** the transport (the `PageFetcher`), or the list UI.

## Seam

`PageFetcher<T> = Future<PageResult<T>> Function(Object? cursor)` — `cursor` is
null for the first page. `PageResult<T> { items, nextCursor }`; `nextCursor ==
null` ⇒ end. The opaque cursor supports offset / token / cursor pagination.

## State

```dart
enum PagingStatus { initial, loadingFirst, loaded, loadingMore, end, error }

class PagingState<T> extends BlocState {
  final List<T> items;
  final PagingStatus status;
  final Object? nextCursor;
  final String? error;
  bool get hasMore; bool get isLoadingMore; bool get isEmpty;
}
```

Groups: `paging:items`, `paging:status`.

## Behavior

- **refresh** → fetch(null), replace items; existing items stay visible during
  the load. `loaded` or `end` on success.
- **loadMore** → guarded (no-op if loading, at end, or not yet loaded);
  fetch(nextCursor), append. Keeps items + cursor on error.
- **retry** → first page if the list is empty, else the next page.

Generics note: events are **non-generic** (config is applied via the factory),
so Juice's type-keyed dispatch matches cleanly; the use cases carry `<T>`.

## Events & use cases (4)

| Event | Concurrency | Behavior |
|---|---|---|
| `InitializePagingEvent` | `droppable` | Await first-page refresh when configured |
| `RefreshPageEvent` | `droppable` | Fetch and replace the first page |
| `LoadMoreEvent` | `droppable` | Fetch and append the next page |
| `RetryPageEvent` | `droppable` | Await the appropriate delegated load |

The bloc-wide loading guard remains intentional: modes exclude only same-type
events, while refresh and load-more must also exclude each other.

API: `refresh`, `loadMore`, `retry`.

## Testing

Fake offset backend: first-page-on-init, loadMore appends to end, gated
same-type loadMore requests coalesce, gated refresh excludes loadMore,
refresh reloads, first-page error → error → retry recovers, loadMore error
keeps items → retry resumes. 8 tests.

## Spec Version

| Version | Date | Status |
|---|---|---|
| 1.1 | 2026-08-12 | Explicit concurrency and cross-event exclusion coverage |
| 1.0 | 2026-05-28 | Implemented |
