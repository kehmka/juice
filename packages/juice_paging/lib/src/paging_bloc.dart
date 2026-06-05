import 'package:juice/juice.dart';

import 'page_fetcher.dart';
import 'paging_config.dart';
import 'paging_events.dart';
import 'paging_state.dart';
import 'use_cases/initialize_paging_use_case.dart';
import 'use_cases/load_more_use_case.dart';
import 'use_cases/refresh_page_use_case.dart';
import 'use_cases/retry_page_use_case.dart';

/// A generic paged / infinite-scroll list bloc.
///
/// Fetches pages through a cursor-based [PageFetcher] seam, appending on
/// `loadMore` and replacing on `refresh`. A single in-flight guard prevents
/// overlapping loads (e.g. a scroll trigger firing twice).
///
/// ```dart
/// final feed = PagingBloc<Post>.withConfig(PagingConfig(
///   fetcher: (cursor) async {
///     final page = await api.posts(after: cursor as String?);
///     return PageResult(page.items, nextCursor: page.next);
///   },
/// ));
/// // in a scroll listener: feed.loadMore();
/// ```
class PagingBloc<T> extends JuiceBloc<PagingState<T>> {
  late PagingConfig<T> _config;
  bool _loading = false;

  PagingBloc()
      : super(
          PagingState<T>(),
          [
            () => UseCaseBuilder(
                typeOfEvent: InitializePagingEvent,
                useCaseGenerator: () => InitializePagingUseCase<T>()),
            () => UseCaseBuilder(
                typeOfEvent: RefreshPageEvent,
                useCaseGenerator: () => RefreshPageUseCase<T>()),
            () => UseCaseBuilder(
                typeOfEvent: LoadMoreEvent,
                useCaseGenerator: () => LoadMoreUseCase<T>()),
            () => UseCaseBuilder(
                typeOfEvent: RetryPageEvent,
                useCaseGenerator: () => RetryPageUseCase<T>()),
          ],
        );

  /// Create, apply config, and trigger the first load.
  factory PagingBloc.withConfig(PagingConfig<T> config) {
    final bloc = PagingBloc<T>();
    bloc.configure(config);
    bloc.send(InitializePagingEvent());
    return bloc;
  }

  void configure(PagingConfig<T> config) => _config = config;
  PagingConfig<T> get config => _config;
  PageFetcher<T> get fetcher => _config.fetcher;

  /// In-flight guard so refresh/loadMore can't overlap.
  bool get isLoading => _loading;
  void beginLoad() => _loading = true;
  void endLoad() => _loading = false;

  // === Convenience API ===

  void refresh() => send(RefreshPageEvent());
  void loadMore() => send(LoadMoreEvent());
  void retry() => send(RetryPageEvent());
}
