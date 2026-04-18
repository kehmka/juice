// Juice features demonstrated:
// - [InlineUseCaseBuilder]: View mode toggle and sort order change are
//   trivial state mutations — perfect for inline lambdas instead of
//   separate use case class files.
// - [StateRelay]: When settings change, a [SettingsChangedEvent] auto-
//   dispatches to [NotesBloc] so it re-sorts/re-layouts. Zero manual
//   event forwarding — the relay watches this bloc's state and fires
//   events to NotesBloc automatically.
import 'package:juice/juice.dart';
import 'package:juice_storage/juice_storage.dart';
import '../rebuild_groups.dart';
import '../notes/notes_bloc.dart';
import '../notes/notes_events.dart';
import 'settings_state.dart';
import 'settings_events.dart';

class SettingsBloc extends JuiceBloc<SettingsState> {
  late final StateRelay<SettingsBloc, NotesBloc, SettingsState> _settingsRelay;

  SettingsBloc()
      : super(
          const SettingsState(),
          [
            // Load persisted preferences — class-based because it involves I/O
            () => UseCaseBuilder(
                  typeOfEvent: LoadSettingsEvent,
                  useCaseGenerator: () => _LoadSettingsUseCase(),
                  initialEventBuilder: () => LoadSettingsEvent(),
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
                      newState:
                          ctx.state.copyWith(sortOrder: event.sortOrder),
                      groups: {SettingsGroups.sort},
                    );
                  },
                ),
          ],
        ) {
    // StateRelay: when SettingsBloc state changes, auto-dispatch to NotesBloc.
    // This is cross-bloc reactivity with zero manual wiring.
    _settingsRelay = StateRelay<SettingsBloc, NotesBloc, SettingsState>(
      toEvent: (state) => SettingsChangedEvent(
        sortOrder: state.sortOrder,
        viewMode: state.viewMode,
      ),
    );
  }

  @override
  Future<void> close() async {
    await _settingsRelay.close();
    await super.close();
  }
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
