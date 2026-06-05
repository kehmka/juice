import 'package:juice/juice.dart';

import '../paging_bloc.dart';
import '../paging_events.dart';
import '../paging_state.dart';

/// Handles [RefreshPageEvent] — load the first page, replacing existing items.
/// Existing items stay visible while the first page loads.
class RefreshPageUseCase<T> extends BlocUseCase<PagingBloc<T>, RefreshPageEvent> {
  @override
  Future<void> execute(RefreshPageEvent event) async {
    if (bloc.isLoading) return;
    bloc.beginLoad();
    try {
      emitUpdate(
        newState: bloc.state.copyWith(
            status: PagingStatus.loadingFirst, error: null),
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
    } catch (e) {
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
