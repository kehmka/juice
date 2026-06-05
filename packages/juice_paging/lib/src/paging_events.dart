import 'package:juice/juice.dart';

/// Base class for paging events.
abstract class PagingEvent extends EventBase {
  @override
  String toString() => runtimeType.toString();
}

/// Trigger the initial load (config is applied directly via the factory).
class InitializePagingEvent extends PagingEvent {}

/// (Re)load from the first page, replacing existing items.
class RefreshPageEvent extends PagingEvent {}

/// Load the next page, appending to existing items.
class LoadMoreEvent extends PagingEvent {}

/// Retry the last failed load (first page or next page).
class RetryPageEvent extends PagingEvent {}
