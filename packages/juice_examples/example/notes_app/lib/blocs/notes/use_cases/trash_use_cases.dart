// Juice features demonstrated:
// - Multiple Hive boxes: MoveToTrash moves notes between 'notes' and 'trash'.
// - TTL on Hive writes: Trashed notes auto-purge after 30 days.
// - [CancellableEvent]: EmptyTrashUseCase checks [isCancelled] between each
//   delete, allowing the user to abort a batch operation mid-flight.
import 'dart:convert';
import 'package:juice/juice.dart';
import 'package:juice_storage/juice_storage.dart';
import '../../rebuild_groups.dart';
import '../notes_bloc.dart';
import '../notes_events.dart';

/// Soft-deletes a note by moving it from 'notes' box to 'trash' box with
/// a 30-day TTL. After 30 days, Hive automatically expires the entry.
class MoveToTrashUseCase extends BlocUseCase<NotesBloc, MoveToTrashEvent> {
  @override
  Future<void> execute(MoveToTrashEvent event) async {
    try {
      final storage = BlocScope.get<StorageBloc>();
      final note =
          bloc.state.notes.firstWhere((n) => n.id == event.noteId);
      final trashedNote = note.copyWith(isTrashed: true);

      // Move: delete from 'notes', write to 'trash' with 30-day TTL
      await storage.hiveDelete('notes', note.id);
      await storage.hiveWrite(
        'trash',
        note.id,
        jsonEncode(trashedNote.toJson()),
        ttl: const Duration(days: 30),
      );

      final updatedNotes = bloc.state.notes
          .map((n) => n.id == event.noteId ? trashedNote : n)
          .toList();

      log('Note "${note.title}" moved to trash (expires in 30 days)');

      emitUpdate(
        newState: bloc.state.copyWith(notes: updatedNotes),
        groupsToRebuild:
            {NotesGroups.list, NotesGroups.trash}.toStringSet(),
      );
    } catch (e, stackTrace) {
      logError(e, stackTrace);
      emitFailure(newState: bloc.state, error: e, errorStackTrace: stackTrace);
    }
  }
}

/// Restores a note from 'trash' box back to 'notes' box.
class RestoreFromTrashUseCase
    extends BlocUseCase<NotesBloc, RestoreFromTrashEvent> {
  @override
  Future<void> execute(RestoreFromTrashEvent event) async {
    try {
      final storage = BlocScope.get<StorageBloc>();
      final note =
          bloc.state.notes.firstWhere((n) => n.id == event.noteId);
      final restoredNote = note.copyWith(isTrashed: false);

      // Move: delete from 'trash', write to 'notes' (no TTL)
      await storage.hiveDelete('trash', note.id);
      await storage.hiveWrite(
          'notes', note.id, jsonEncode(restoredNote.toJson()));

      final updatedNotes = bloc.state.notes
          .map((n) => n.id == event.noteId ? restoredNote : n)
          .toList();

      log('Note "${note.title}" restored from trash');

      emitUpdate(
        newState: bloc.state.copyWith(notes: updatedNotes),
        groupsToRebuild:
            {NotesGroups.trash, NotesGroups.list}.toStringSet(),
      );
    } catch (e, stackTrace) {
      logError(e, stackTrace);
      emitFailure(newState: bloc.state, error: e, errorStackTrace: stackTrace);
    }
  }
}

/// Empties all trashed notes. Uses [CancellableEvent] — the user can cancel
/// the batch deletion mid-operation by calling event.cancel().
class EmptyTrashUseCase extends BlocUseCase<NotesBloc, EmptyTrashEvent> {
  @override
  Future<void> execute(EmptyTrashEvent event) async {
    final trashedNotes = bloc.state.trashedNotes;
    if (trashedNotes.isEmpty) return;

    emitWaiting(newState: bloc.state);
    final storage = BlocScope.get<StorageBloc>();
    var deleted = 0;

    try {
      for (final note in trashedNotes) {
        // Check for cancellation between each delete
        if (event.isCancelled) {
          log('Empty trash cancelled after $deleted/${trashedNotes.length}');
          // Remove only the notes we've already deleted
          final deletedIds =
              trashedNotes.take(deleted).map((n) => n.id).toSet();
          emitCancel(
            newState: bloc.state.copyWith(
              notes: bloc.state.notes
                  .where((n) => !deletedIds.contains(n.id))
                  .toList(),
            ),
            groupsToRebuild: {NotesGroups.trash}.toStringSet(),
          );
          return;
        }

        await storage.hiveDelete('trash', note.id);
        deleted++;
      }

      final updatedNotes =
          bloc.state.notes.where((n) => !n.isTrashed).toList();

      log('Emptied trash ($deleted notes permanently deleted)');

      emitUpdate(
        newState: bloc.state.copyWith(notes: updatedNotes),
        groupsToRebuild:
            {NotesGroups.trash, NotesGroups.list}.toStringSet(),
      );
    } catch (e, stackTrace) {
      logError(e, stackTrace);
      emitFailure(newState: bloc.state, error: e, errorStackTrace: stackTrace);
    }
  }
}

/// Permanently deletes a single note from the 'trash' box.
class PermanentDeleteUseCase
    extends BlocUseCase<NotesBloc, PermanentDeleteEvent> {
  @override
  Future<void> execute(PermanentDeleteEvent event) async {
    try {
      final storage = BlocScope.get<StorageBloc>();
      await storage.hiveDelete('trash', event.noteId);

      final updatedNotes =
          bloc.state.notes.where((n) => n.id != event.noteId).toList();

      emitUpdate(
        newState: bloc.state.copyWith(notes: updatedNotes),
        groupsToRebuild: {NotesGroups.trash}.toStringSet(),
      );
    } catch (e, stackTrace) {
      logError(e, stackTrace);
      emitFailure(newState: bloc.state, error: e, errorStackTrace: stackTrace);
    }
  }
}
