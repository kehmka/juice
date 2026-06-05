import 'package:juice/juice.dart';

/// Load lifecycle of a paged list.
enum PagingStatus {
  /// No load attempted yet.
  initial,

  /// Loading the first page (empty list).
  loadingFirst,

  /// Idle with items loaded; more may be available.
  loaded,

  /// Loading a subsequent page (items already shown).
  loadingMore,

  /// All pages loaded — no more to fetch.
  end,

  /// A load failed. [PagingState.error] holds the message; existing items stay.
  error,
}

/// Rebuild groups emitted by `PagingBloc`.
abstract final class PagingGroups {
  /// The item list changed.
  static const items = 'paging:items';

  /// Load status / error changed (drives spinners + retry).
  static const status = 'paging:status';

  static const all = {items, status};
}

/// Immutable paged-list state.
class PagingState<T> extends BlocState {
  final List<T> items;
  final PagingStatus status;

  /// Cursor for the next page (null = none fetched yet or at the end).
  final Object? nextCursor;

  final String? error;

  const PagingState({
    this.items = const [],
    this.status = PagingStatus.initial,
    this.nextCursor,
    this.error,
  });

  /// Initial state for items of type [T].
  static PagingState<T> initial<T>() => PagingState<T>();

  bool get isLoadingFirst => status == PagingStatus.loadingFirst;
  bool get isLoadingMore => status == PagingStatus.loadingMore;
  bool get hasMore =>
      status != PagingStatus.end && status != PagingStatus.loadingFirst;
  bool get isEmpty => items.isEmpty;

  PagingState<T> copyWith({
    List<T>? items,
    PagingStatus? status,
    Object? nextCursor = _unset,
    Object? error = _unset,
  }) {
    return PagingState<T>(
      items: items ?? this.items,
      status: status ?? this.status,
      nextCursor: identical(nextCursor, _unset) ? this.nextCursor : nextCursor,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }

  @override
  String toString() =>
      'PagingState(${items.length} items, $status, hasMore: $hasMore)';
}

const Object _unset = Object();
