import 'package:juice/juice.dart';

/// Base class for paging events.
abstract class PagingEvent extends EventBase {
  @override
  String toString() => runtimeType.toString();
}

/// Trigger the initial load (config is applied directly via the factory).
class InitializePagingEvent extends PagingEvent {}

/// (Re)load from the first page, replacing existing items.
///
/// A result event: `await bloc.sendForResult(RefreshPageEvent())` completes
/// when the first page is in state (what a pull-to-refresh awaits), and
/// throws what the fetcher threw. It is `singleflight`: a refresh requested
/// while one is running joins it.
///
/// A refresh that arrives while a load-MORE is running is not run — the two
/// never overlap. `PagingBloc.refresh()` is then a no-op; the awaited form
/// throws a [StateError] saying so.
class RefreshPageEvent extends ResultEvent<void> implements PagingEvent {
  RefreshPageEvent();

  @override
  String toString() => runtimeType.toString();
}

/// Load the next page, appending to existing items.
class LoadMoreEvent extends PagingEvent {}

/// Retry the last failed load (first page or next page).
class RetryPageEvent extends PagingEvent {}
