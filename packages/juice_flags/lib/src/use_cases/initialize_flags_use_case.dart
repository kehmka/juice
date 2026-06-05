import 'package:juice/juice.dart';

import '../flags_bloc.dart';
import '../flags_events.dart';
import '../flags_state.dart';

/// Handles [InitializeFlagsEvent] — seed defaults, subscribe to live updates,
/// optionally kick off the first fetch.
class InitializeFlagsUseCase extends BlocUseCase<FlagsBloc, InitializeFlagsEvent> {
  @override
  Future<void> execute(InitializeFlagsEvent event) async {
    bloc.configure(event.config);
    bloc.startListening();

    final resolved = bloc.resolve();
    emitUpdate(
      newState: bloc.state.copyWith(values: resolved),
      groupsToRebuild: {
        FlagsGroups.any,
        FlagsGroups.status,
        ...resolved.keys.map(FlagsGroups.flag),
      },
    );

    if (event.config.fetchOnInit) {
      bloc.send(RefreshFlagsEvent());
    }
  }
}
