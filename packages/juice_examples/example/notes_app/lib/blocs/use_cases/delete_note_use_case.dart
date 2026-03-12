import 'package:juice/juice.dart';
import 'package:juice_storage/juice_storage.dart';
import '../notes_bloc.dart';
import '../notes_events.dart';

class DeleteNoteUseCase extends UseCase<NotesBloc, DeleteNoteEvent> {
  @override
  Future<void> execute(DeleteNoteEvent event) async {
    final storageBloc = BlocScope.get<StorageBloc>();
    await storageBloc.hiveDelete('notes', event.noteId);

    final updatedNotes =
        bloc.state.notes.where((n) => n.id != event.noteId).toList();
    final activeNote = bloc.state.activeNote?.id == event.noteId
        ? null
        : bloc.state.activeNote;

    emitUpdate(
      newState: bloc.state.copyWith(
        notes: updatedNotes,
        activeNote: activeNote,
        clearActiveNote: activeNote == null,
      ),
    );
  }
}
