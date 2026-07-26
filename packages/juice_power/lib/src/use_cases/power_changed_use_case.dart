import 'package:juice/juice.dart';

import '../power_bloc.dart';
import '../power_events.dart';
import '../power_state.dart';

/// Handles [PowerChangedEvent].
///
/// Emits only when something actually moved, with precise rebuild groups — the
/// level poll fires every minute and would otherwise wake every consumer for a
/// number that had not changed.
class PowerChangedUseCase extends BlocUseCase<PowerBloc, PowerChangedEvent> {
  @override
  Future<void> execute(PowerChangedEvent event) async {
    final s = event.snapshot;
    final state = bloc.state;

    final sourceChanged = s.status != state.status;
    final levelChanged = s.percent != state.percent;
    final saverChanged = s.saverOn != state.saverOn;
    if (!sourceChanged && !levelChanged && !saverChanged) return; // no-op

    final groups = <String>{};
    if (sourceChanged) groups.add(PowerGroups.source);
    if (levelChanged) groups.add(PowerGroups.level);
    if (saverChanged) groups.add(PowerGroups.saver);

    emitUpdate(
      newState: state.copyWith(
        status: s.status,
        percent: s.percent,
        saverOn: s.saverOn,
        lastChangedAt: DateTime.now(),
      ),
      groupsToRebuild: groups,
    );
  }
}
