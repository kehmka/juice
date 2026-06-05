import 'package:juice/juice.dart';

import '../paging_bloc.dart';
import '../paging_events.dart';

/// Handles [RetryPageEvent] — retry whichever load failed: the first page if the
/// list is empty, otherwise the next page.
class RetryPageUseCase<T> extends BlocUseCase<PagingBloc<T>, RetryPageEvent> {
  @override
  Future<void> execute(RetryPageEvent event) async {
    if (bloc.state.items.isEmpty) {
      bloc.send(RefreshPageEvent());
    } else {
      bloc.send(LoadMoreEvent());
    }
  }
}
