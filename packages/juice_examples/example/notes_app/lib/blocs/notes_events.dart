import 'package:juice/juice.dart';
import 'notes_state.dart';

class LoadNotesEvent extends EventBase {
  LoadNotesEvent() : super(groupsToRebuild: {'notes:list'});
}

class SaveNoteEvent extends EventBase {
  final String? id;
  final String title;
  final String body;

  SaveNoteEvent({
    this.id,
    required this.title,
    required this.body,
  }) : super(groupsToRebuild: {'notes:list', 'notes:editor'});
}

class DeleteNoteEvent extends EventBase {
  final String noteId;

  DeleteNoteEvent({required this.noteId})
      : super(groupsToRebuild: {'notes:list'});
}

class SearchNotesEvent extends EventBase {
  final String query;

  SearchNotesEvent({required this.query})
      : super(groupsToRebuild: {'notes:search', 'notes:list'});
}

class SelectNoteEvent extends EventBase {
  final String noteId;

  SelectNoteEvent({required this.noteId})
      : super(groupsToRebuild: {'notes:editor'});
}

class ChangeSortOrderEvent extends EventBase {
  final NotesSortOrder sortOrder;

  ChangeSortOrderEvent({required this.sortOrder})
      : super(groupsToRebuild: {'notes:list'});
}
