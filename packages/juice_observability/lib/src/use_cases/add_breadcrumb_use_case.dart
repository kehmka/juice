import 'package:juice/juice.dart';

import '../observability_bloc.dart';
import '../observability_events.dart';
import '../observability_state.dart';

/// Handles [AddBreadcrumbEvent] — append to the breadcrumb ring (trimmed to
/// `maxBreadcrumbs`) and forward to the reporters.
///
/// The builder registers this `sequential`, so the read-append-trim of
/// `state.breadcrumbs` across the `await` is race-free — no bloc-side ring.
class AddBreadcrumbUseCase
    extends BlocUseCase<ObservabilityBloc, AddBreadcrumbEvent> {
  @override
  Future<void> execute(AddBreadcrumbEvent event) async {
    if (bloc.maxBreadcrumbs <= 0 || !bloc.state.enabled) return;

    final crumbs = [...bloc.state.breadcrumbs, event.crumb];
    final trimmed = crumbs.length > bloc.maxBreadcrumbs
        ? crumbs.sublist(crumbs.length - bloc.maxBreadcrumbs)
        : crumbs;

    await bloc.fanOut((r) => r.addBreadcrumb(event.crumb));

    emitUpdate(
      newState: bloc.state.copyWith(breadcrumbs: trimmed),
      groupsToRebuild: {ObservabilityGroups.status},
    );
  }
}
