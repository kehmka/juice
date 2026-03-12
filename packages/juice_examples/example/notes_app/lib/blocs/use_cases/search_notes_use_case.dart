import 'package:juice/juice.dart';
import 'package:juice_storage/juice_storage.dart';
import '../notes_bloc.dart';
import '../notes_events.dart';

class SearchNotesUseCase extends UseCase<NotesBloc, SearchNotesEvent> {
  @override
  Future<void> execute(SearchNotesEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(searchQuery: event.query),
    );
  }
}

class SelectNoteUseCase extends UseCase<NotesBloc, SelectNoteEvent> {
  @override
  Future<void> execute(SelectNoteEvent event) async {
    final note = bloc.state.notes.firstWhere((n) => n.id == event.noteId);
    emitUpdate(
      newState: bloc.state.copyWith(activeNote: note),
    );
  }
}

class ChangeSortOrderUseCase
    extends UseCase<NotesBloc, ChangeSortOrderEvent> {
  @override
  Future<void> execute(ChangeSortOrderEvent event) async {
    final storageBloc = BlocScope.get<StorageBloc>();
    await storageBloc.prefsWrite<String>(
      'notes_sort_order',
      event.sortOrder.name,
    );

    emitUpdate(
      newState: bloc.state.copyWith(sortOrder: event.sortOrder),
    );
  }
}
