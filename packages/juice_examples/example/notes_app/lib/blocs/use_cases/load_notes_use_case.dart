import 'dart:convert';
import 'package:juice/juice.dart';
import 'package:juice_storage/juice_storage.dart';
import '../notes_bloc.dart';
import '../notes_state.dart';
import '../notes_events.dart';
import '../../models/note.dart';

class LoadNotesUseCase extends UseCase<NotesBloc, LoadNotesEvent> {
  @override
  Future<void> execute(LoadNotesEvent event) async {
    emitWaiting(newState: bloc.state.copyWith(isLoading: true));

    final storageBloc = BlocScope.get<StorageBloc>();
    final keys = await storageBloc.hiveKeys('notes');

    final notes = <Note>[];
    for (final key in keys) {
      final json = await storageBloc.hiveRead<String>('notes', key);
      if (json != null) {
        notes.add(Note.fromJson(jsonDecode(json) as Map<String, dynamic>));
      }
    }

    final sortPref = await storageBloc.prefsRead<String>('notes_sort_order');
    final sortOrder = _parseSortOrder(sortPref);

    emitUpdate(
      newState: bloc.state.copyWith(
        notes: notes,
        sortOrder: sortOrder,
        isLoading: false,
      ),
    );
  }

  NotesSortOrder _parseSortOrder(String? value) {
    switch (value) {
      case 'updatedAsc':
        return NotesSortOrder.updatedAsc;
      case 'titleAsc':
        return NotesSortOrder.titleAsc;
      case 'titleDesc':
        return NotesSortOrder.titleDesc;
      default:
        return NotesSortOrder.updatedDesc;
    }
  }
}
