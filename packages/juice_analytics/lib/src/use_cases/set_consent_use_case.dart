import 'package:juice/juice.dart';

import '../analytics_bloc.dart';
import '../analytics_events.dart';
import '../analytics_state.dart';

/// Handles [SetConsentEvent] — grant or revoke tracking consent.
class SetConsentUseCase extends BlocUseCase<AnalyticsBloc, SetConsentEvent> {
  @override
  Future<void> execute(SetConsentEvent event) async {
    if (event.enabled == bloc.state.enabled) return;
    emitUpdate(
      newState: bloc.state.copyWith(enabled: event.enabled),
      groupsToRebuild: {AnalyticsGroups.status},
    );
  }
}
