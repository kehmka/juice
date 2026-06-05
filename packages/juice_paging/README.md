# juice_paging

Paged / infinite-scroll list state as a generic [Juice](https://pub.dev/packages/juice)
bloc, behind a cursor-based fetcher seam.

[![pub package](https://img.shields.io/pub/v/juice_paging.svg)](https://pub.dev/packages/juice_paging)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

## What it owns

The list of loaded items + load status (first page, loading-more, end, error).
It does **not** own the transport — you supply a `PageFetcher`.

## Install

```yaml
dependencies:
  juice_paging: ^0.1.0
```

## Use

```dart
final feed = PagingBloc<Post>.withConfig(PagingConfig(
  fetcher: (cursor) async {
    final page = await api.posts(after: cursor as String?);
    return PageResult(page.items, nextCursor: page.next);  // null next => end
  },
));

feed.loadMore();   // append next page
feed.refresh();    // reload from the first page
feed.retry();      // retry the failed load
```

The cursor is **opaque** — return an offset, a token, a timestamp, whatever your
backend uses. `nextCursor: null` means there are no more pages.

## Infinite scroll

```dart
NotificationListener<ScrollNotification>(
  onNotification: (n) {
    if (n.metrics.pixels >= n.metrics.maxScrollExtent - 300) feed.loadMore();
    return false;
  },
  child: ListView.builder(...),
)
```

`loadMore` is **guarded** — it no-ops while a load is in flight or at the end, so
firing it on every scroll frame is safe.

## State

| Field / getter | Meaning |
|---|---|
| `items` | loaded items (`List<T>`) |
| `status` | initial / loadingFirst / loaded / loadingMore / end / error |
| `nextCursor` | cursor for the next page |
| `error` | last load error (items are kept) |
| `hasMore` / `isLoadingMore` / `isEmpty` | derived |

A failed `loadMore` keeps items + cursor; `retry()` resumes the next page. A
failed first page → `error` with an empty list; `retry()` reloads it.

Rebuild groups: `paging:items`, `paging:status`.

## License

MIT License — see [LICENSE](LICENSE).
