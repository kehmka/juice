// Juice features demonstrated:
// - [InlineUseCaseBuilder]: View mode toggle and sort order change are
//   trivial state mutations — perfect for inline lambdas instead of
//   separate use case class files.
// - [StateRelay] (wired in main.dart): when settings change, a
//   [SettingsChangedEvent] auto-dispatches to [NotesBloc] so it re-sorts /
//   re-layouts — zero manual event forwarding. The relay leases both blocs,
//   so it is built in the composition root, never inside a bloc's own
//   constructor.
import 'package:juice/juice.dart';
import 'package:juice_storage/juice_storage.dart';
import '../rebuild_groups.dart';
import 'settings_state.dart';
import 'settings_events.dart';

class SettingsBloc extends JuiceBloc<SettingsState> {
  SettingsBloc()
      : super(
          const SettingsState(),
          [
            // Load persisted preferences — class-based because it involves I/O
            () => UseCaseBuilder(
                  typeOfEvent: LoadSettingsEvent,
                  useCaseGenerator: () => _LoadSettingsUseCase(),
                  initialEventBuilder: () => LoadSettingsEvent(),
                  concurrency: EventConcurrency.droppable,
                ),

            // Toggle grid/list — a one-liner toggle, perfect for inline
            () => InlineUseCaseBuilder<SettingsBloc, SettingsState,
                    ToggleViewModeEvent>(
                  typeOfEvent: ToggleViewModeEvent,
                  handler: (ctx, event) async {
                    final newMode = ctx.state.viewMode == ViewMode.list
                        ? ViewMode.grid
                        : ViewMode.list;
                    final storage = BlocScope.get<StorageBloc>();
                    await storage.prefsWrite('view_mode', newMode.name);
                    ctx.emit.update(
                      newState: ctx.state.copyWith(viewMode: newMode),
                      groups: {SettingsGroups.viewMode},
                    );
                  },
                  concurrency: EventConcurrency.sequential,
                ),

            // Change sort order — also simple enough for inline
            () => InlineUseCaseBuilder<SettingsBloc, SettingsState,
                    ChangeSortOrderEvent>(
                  typeOfEvent: ChangeSortOrderEvent,
                  handler: (ctx, event) async {
                    final storage = BlocScope.get<StorageBloc>();
                    await storage.prefsWrite(
                        'sort_order', event.sortOrder.name);
                    ctx.emit.update(
                      newState: ctx.state.copyWith(sortOrder: event.sortOrder),
                      groups: {SettingsGroups.sort},
                    );
                  },
                  concurrency: EventConcurrency.sequential,
                ),
          ],
        );
}

/// Loads persisted view mode and sort order from SharedPreferences.
class _LoadSettingsUseCase
    extends BlocUseCase<SettingsBloc, LoadSettingsEvent> {
  @override
  Future<void> execute(LoadSettingsEvent event) async {
    try {
      final storage = BlocScope.get<StorageBloc>();
      final viewModeName = await storage.prefsRead<String>('view_mode');
      final sortOrderName = await storage.prefsRead<String>('sort_order');

      final viewMode = ViewMode.values.firstWhere(
        (v) => v.name == viewModeName,
        orElse: () => ViewMode.list,
      );
      final sortOrder = SortOrder.values.firstWhere(
        (s) => s.name == sortOrderName,
        orElse: () => SortOrder.updatedDesc,
      );

      emitUpdate(
        newState: bloc.state.copyWith(
          viewMode: viewMode,
          sortOrder: sortOrder,
        ),
      );
    } catch (e, stackTrace) {
      logError(e, stackTrace);
      emitFailure(newState: bloc.state, error: e, errorStackTrace: stackTrace);
    }
  }
}
