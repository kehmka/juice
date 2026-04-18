import 'dart:convert';
import 'package:juice/juice.dart';
import 'package:juice_storage/juice_storage.dart';
import '../../../models/note.dart';
import '../notes_bloc.dart';
import '../notes_events.dart';

class SaveNoteUseCase extends BlocUseCase<NotesBloc, SaveNoteEvent> {
  @override
  Future<void> execute(SaveNoteEvent event) async {
    try {
      final now = DateTime.now();
      final isNew = event.id == null;

      // Preserve createdAt for existing notes
      DateTime createdAt = now;
      bool existingPinned = false;
      NoteColor existingColor = NoteColor.none;
      if (!isNew) {
        final existing = bloc.state.notes
            .where((n) => n.id == event.id)
            .firstOrNull;
        if (existing != null) {
          createdAt = existing.createdAt;
          existingPinned = existing.isPinned;
          existingColor = existing.color;
        }
      }

      final note = Note(
        id: event.id ?? now.millisecondsSinceEpoch.toString(),
        title: event.title.isEmpty ? 'Untitled' : event.title,
        body: event.body,
        createdAt: createdAt,
        updatedAt: now,
        isPinned: event.isPinned ?? existingPinned,
        color: event.color ?? existingColor,
      );

      final storage = BlocScope.get<StorageBloc>();
      await storage.hiveWrite<String>(
          'notes', note.id, jsonEncode(note.toJson()));

      final updatedNotes = List<Note>.from(bloc.state.notes);
      final existingIndex =
          updatedNotes.indexWhere((n) => n.id == note.id);
      if (existingIndex >= 0) {
        updatedNotes[existingIndex] = note;
      } else {
        updatedNotes.add(note);
      }

      log('Note "${note.title}" saved');

      emitUpdate(newState: bloc.state.copyWith(notes: updatedNotes));
    } catch (e, stackTrace) {
      logError(e, stackTrace);
      emitFailure(newState: bloc.state, error: e, errorStackTrace: stackTrace);
    }
  }
}
