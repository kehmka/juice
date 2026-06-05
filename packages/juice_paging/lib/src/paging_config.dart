import 'page_fetcher.dart';

/// Configures a `PagingBloc`.
class PagingConfig<T> {
  /// Fetches one page given a cursor. **Required.**
  final PageFetcher<T> fetcher;

  /// Load the first page on initialization.
  final bool loadOnInit;

  const PagingConfig({
    required this.fetcher,
    this.loadOnInit = true,
  });
}
