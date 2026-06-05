/// One page of results plus the cursor to fetch the next.
///
/// [nextCursor] is opaque — an offset, a token, a timestamp, whatever your
/// backend uses. Null means there are no more pages.
class PageResult<T> {
  final List<T> items;
  final Object? nextCursor;

  const PageResult(this.items, {this.nextCursor});

  bool get hasMore => nextCursor != null;
}

/// Fetches one page. [cursor] is null for the first page, otherwise the
/// [PageResult.nextCursor] from the previous page. Throw to surface a load error.
///
/// Works for cursor, token, or offset pagination — encode whatever you need in
/// the cursor.
typedef PageFetcher<T> = Future<PageResult<T>> Function(Object? cursor);
