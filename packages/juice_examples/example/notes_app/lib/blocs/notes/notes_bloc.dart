// Juice features demonstrated:
// - [InlineUseCaseBuilder]: Toggle pin, change color, and search are simple
//   state mutations — no separate class files needed.
// - [BlocUseCase]: Load, save, and trash operations use class-based use cases
//   with automatic logging and error handling.
// - [CancellableEvent]: EmptyTrashEvent is cancellable — the user can abort
//   a batch deletion mid-operation.
// - [skipIfSame]: Search emits with skipIfSame to prevent redundant rebuilds
//   when the query hasn't changed (e.g., same debounced value sent twice).
// - [StateRelay]: SettingsChangedEvent arrives automatically from SettingsBloc
//   via StateRelay — zero manual forwarding.
import 'dart:convert';
import 'package:juice/juice.dart';
import 'package:juice_storage/juice_storage.dart';
import '../../models/note.dart';
import '../rebuild_groups.dart';
import 'notes_state.dart';
import 'notes_events.dart';
import 'use_cases/load_notes_use_case.dart';
import 'use_cases/save_note_use_case.dart';
import 'use_cases/trash_use_cases.dart';

class NotesBloc extends JuiceBloc<NotesState> {
  NotesBloc()
      : super(
          const NotesState(),
          [
            // Load all notes from Hive — class-based (I/O + multiple boxes)
            () => UseCaseBuilder(
                  typeOfEvent: LoadNotesEvent,
                  useCaseGenerator: () => LoadNotesUseCase(),
                  initialEventBuilder: () => LoadNotesEvent(),
                ),

            // Save note — class-based (I/O + error handling)
            () => UseCaseBuilder(
                  typeOfEvent: SaveNoteEvent,
                  useCaseGenerator: () => SaveNoteUseCase(),
                ),

            // Search — class-based to use skipIfSame (InlineEmitter doesn't
            // support it). Prevents redundant rebuilds when the query hasn't
            // actually changed.
            () => UseCaseBuilder(
                  typeOfEvent: SearchNotesEvent,
                  useCaseGenerator: () => _SearchUseCase(),
                ),

            // Toggle pin — trivial toggle, perfect for inline
            () => InlineUseCaseBuilder<NotesBloc, NotesState, TogglePinEvent>(
                  typeOfEvent: TogglePinEvent,
                  handler: (ctx, event) async {
                    final notes = List<Note>.from(ctx.state.notes);
                    final idx =
                        notes.indexWhere((n) => n.id == event.noteId);
                    if (idx < 0) return;
                    notes[idx] =
                        notes[idx].copyWith(isPinned: !notes[idx].isPinned);
                    final storage = BlocScope.get<StorageBloc>();
                    await storage.hiveWrite('notes', notes[idx].id,
                        jsonEncode(notes[idx].toJson()));
                    ctx.emit.update(
                      newState: ctx.state.copyWith(notes: notes),
                      groups: {NotesGroups.list},
                    );
                  },
                ),

            // Change note color — trivial mutation, inline
            () => InlineUseCaseBuilder<NotesBloc, NotesState,
                    ChangeNoteColorEvent>(
                  typeOfEvent: ChangeNoteColorEvent,
                  handler: (ctx, event) async {
                    final notes = List<Note>.from(ctx.state.notes);
                    final idx =
                        notes.indexWhere((n) => n.id == event.noteId);
                    if (idx < 0) return;
                    notes[idx] = notes[idx].copyWith(color: event.color);
                    final storage = BlocScope.get<StorageBloc>();
                    await storage.hiveWrite('notes', notes[idx].id,
                        jsonEncode(notes[idx].toJson()));
                    ctx.emit.update(
                      newState: ctx.state.copyWith(notes: notes),
                      groups: {NotesGroups.list},
                    );
                  },
                ),

            // Soft delete — class-based (I/O across two Hive boxes + TTL)
            () => UseCaseBuilder(
                  typeOfEvent: MoveToTrashEvent,
                  useCaseGenerator: () => MoveToTrashUseCase(),
                ),

            // Restore from trash — class-based (I/O across two boxes)
            () => UseCaseBuilder(
                  typeOfEvent: RestoreFromTrashEvent,
                  useCaseGenerator: () => RestoreFromTrashUseCase(),
                ),

            // Empty trash — CancellableEvent for batch operation
            () => UseCaseBuilder(
                  typeOfEvent: EmptyTrashEvent,
                  useCaseGenerator: () => EmptyTrashUseCase(),
                ),

            // Permanent delete single item
            () => UseCaseBuilder(
                  typeOfEvent: PermanentDeleteEvent,
                  useCaseGenerator: () => PermanentDeleteUseCase(),
                ),

            // Settings changed — relay from SettingsBloc, just update local state
            () => InlineUseCaseBuilder<NotesBloc, NotesState,
                    SettingsChangedEvent>(
                  typeOfEvent: SettingsChangedEvent,
                  handler: (ctx, event) async {
                    ctx.emit.update(
                      newState: ctx.state.copyWith(
                        sortOrder: event.sortOrder,
                        viewMode: event.viewMode,
                      ),
                      groups: {NotesGroups.list},
                    );
                  },
                ),
          ],
        );
}

/// Search use case — class-based to use [skipIfSame].
/// Prevents duplicate widget rebuilds when the user types and deletes,
/// landing on the same query string.
class _SearchUseCase extends BlocUseCase<NotesBloc, SearchNotesEvent> {
  @override
  Future<void> execute(SearchNotesEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(searchQuery: event.query),
      skipIfSame: true,
    );
  }
}
