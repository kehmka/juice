import 'dart:convert';
import 'package:juice/juice.dart';
import 'package:juice_storage/juice_storage.dart';
import '../notes_bloc.dart';
import '../notes_events.dart';
import '../../models/note.dart';

class SaveNoteUseCase extends UseCase<NotesBloc, SaveNoteEvent> {
  @override
  Future<void> execute(SaveNoteEvent event) async {
    final now = DateTime.now();
    final isNew = event.id == null;

    final note = Note(
      id: event.id ?? now.millisecondsSinceEpoch.toString(),
      title: event.title.isEmpty ? 'Untitled' : event.title,
      body: event.body,
      createdAt: isNew
          ? now
          : bloc.state.notes
                  .where((n) => n.id == event.id)
                  .firstOrNull
                  ?.createdAt ??
              now,
      updatedAt: now,
    );

    final storageBloc = BlocScope.get<StorageBloc>();
    await storageBloc.hiveWrite<String>(
      'notes',
      note.id,
      jsonEncode(note.toJson()),
    );

    final updatedNotes = List<Note>.from(bloc.state.notes);
    final existingIndex = updatedNotes.indexWhere((n) => n.id == note.id);
    if (existingIndex >= 0) {
      updatedNotes[existingIndex] = note;
    } else {
      updatedNotes.add(note);
    }

    emitUpdate(
      newState: bloc.state.copyWith(
        notes: updatedNotes,
        activeNote: note,
      ),
    );
  }
}
