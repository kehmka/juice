import 'package:juice/juice.dart';

import '../paging_bloc.dart';
import '../paging_events.dart';

/// Handles [InitializePagingEvent] — load the first page if configured.
class InitializePagingUseCase<T>
    extends BlocUseCase<PagingBloc<T>, InitializePagingEvent> {
  @override
  Future<void> execute(InitializePagingEvent event) async {
    if (bloc.config.loadOnInit) {
      bloc.send(RefreshPageEvent());
    }
  }
}
