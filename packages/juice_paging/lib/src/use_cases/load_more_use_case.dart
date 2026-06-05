import 'package:juice/juice.dart';

import '../paging_bloc.dart';
import '../paging_events.dart';
import '../paging_state.dart';

/// Handles [LoadMoreEvent] — fetch the next page and append.
///
/// No-op if a load is in flight or there's nothing more to fetch (so a scroll
/// listener can fire freely).
class LoadMoreUseCase<T> extends BlocUseCase<PagingBloc<T>, LoadMoreEvent> {
  @override
  Future<void> execute(LoadMoreEvent event) async {
    if (bloc.isLoading || !bloc.state.hasMore) return;
    if (bloc.state.status == PagingStatus.initial) return; // refresh first

    bloc.beginLoad();
    try {
      emitUpdate(
        newState: bloc.state.copyWith(status: PagingStatus.loadingMore),
        groupsToRebuild: {PagingGroups.status},
      );

      final page = await bloc.fetcher(bloc.state.nextCursor);
      emitUpdate(
        newState: bloc.state.copyWith(
          items: [...bloc.state.items, ...page.items],
          nextCursor: page.nextCursor,
          status: page.hasMore ? PagingStatus.loaded : PagingStatus.end,
          error: null,
        ),
        groupsToRebuild: {PagingGroups.items, PagingGroups.status},
      );
    } catch (e) {
      // Keep items + cursor so retry resumes from here.
      emitFailure(
        newState: bloc.state.copyWith(
            status: PagingStatus.error, error: e.toString()),
        groupsToRebuild: {PagingGroups.status},
        error: e,
      );
    } finally {
      bloc.endLoad();
    }
  }
}
