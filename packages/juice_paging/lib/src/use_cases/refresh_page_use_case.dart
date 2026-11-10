import 'package:juice/juice.dart';

import '../paging_bloc.dart';
import '../paging_events.dart';
import '../paging_state.dart';

/// Handles [RefreshPageEvent] — load the first page, replacing existing items.
/// Existing items stay visible while the first page loads.
class RefreshPageUseCase<T>
    extends BlocUseCase<PagingBloc<T>, RefreshPageEvent> {
  @override
  Future<void> execute(RefreshPageEvent event) async {
    if (bloc.isLoading) {
      // A load-more is running (another refresh would have been joined, not
      // run). The two never overlap, so this refresh is refused: nothing is
      // emitted, and a caller awaiting it is told why.
      event.fail(
          StateError('RefreshPageEvent was not run: a page is loading. '
              'Refresh again when it has finished.'),
          StackTrace.current);
      return;
    }
    bloc.beginLoad();
    try {
      emitUpdate(
        newState:
            bloc.state.copyWith(status: PagingStatus.loadingFirst, error: null),
        groupsToRebuild: {PagingGroups.status},
      );

      final page = await bloc.fetcher(null);
      emitUpdate(
        newState: bloc.state.copyWith(
          items: page.items,
          nextCursor: page.nextCursor,
          status: page.hasMore ? PagingStatus.loaded : PagingStatus.end,
          error: null,
        ),
        groupsToRebuild: {PagingGroups.items, PagingGroups.status},
      );
      event.succeed(null);
    } catch (e, stackTrace) {
      emitFailure(
        newState: bloc.state
            .copyWith(status: PagingStatus.error, error: e.toString()),
        groupsToRebuild: {PagingGroups.status},
        error: e,
        errorStackTrace: stackTrace,
      );
      // `loadingFirst` was this event's first status, so an awaiting caller
      // is past it and waiting on the result.
      event.fail(e, stackTrace);
    } finally {
      bloc.endLoad();
    }
  }
}
