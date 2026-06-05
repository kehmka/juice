import 'package:juice/juice.dart';

import '../observability_bloc.dart';
import '../observability_events.dart';
import '../observability_state.dart';

/// Handles [AddBreadcrumbEvent] — append to the breadcrumb ring (trimmed to
/// `maxBreadcrumbs`) and forward to the reporters.
class AddBreadcrumbUseCase
    extends BlocUseCase<ObservabilityBloc, AddBreadcrumbEvent> {
  @override
  Future<void> execute(AddBreadcrumbEvent event) async {
    if (bloc.maxBreadcrumbs <= 0 || !bloc.state.enabled) return;

    bloc.addBreadcrumbToRing(event.crumb); // bloc-owned ring (race-safe)
    await bloc.fanOut((r) => r.addBreadcrumb(event.crumb));

    emitUpdate(
      newState: bloc.state.copyWith(breadcrumbs: bloc.breadcrumbs),
      groupsToRebuild: {ObservabilityGroups.status},
    );
  }
}
