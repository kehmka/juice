import 'package:juice/juice.dart';
import '../models/note.dart';

enum NotesSortOrder { updatedDesc, updatedAsc, titleAsc, titleDesc }

class NotesState extends BlocState {
  final List<Note> notes;
  final Note? activeNote;
  final String searchQuery;
  final NotesSortOrder sortOrder;
  final bool isLoading;

  const NotesState({
    this.notes = const [],
    this.activeNote,
    this.searchQuery = '',
    this.sortOrder = NotesSortOrder.updatedDesc,
    this.isLoading = false,
  });

  List<Note> get filteredNotes {
    var result = List<Note>.from(notes);
    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      result = result
          .where((n) =>
              n.title.toLowerCase().contains(query) ||
              n.body.toLowerCase().contains(query))
          .toList();
    }
    switch (sortOrder) {
      case NotesSortOrder.updatedDesc:
        result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case NotesSortOrder.updatedAsc:
        result.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
      case NotesSortOrder.titleAsc:
        result.sort((a, b) => a.title.compareTo(b.title));
      case NotesSortOrder.titleDesc:
        result.sort((a, b) => b.title.compareTo(a.title));
    }
    return result;
  }

  NotesState copyWith({
    List<Note>? notes,
    Note? activeNote,
    String? searchQuery,
    NotesSortOrder? sortOrder,
    bool? isLoading,
    bool clearActiveNote = false,
  }) {
    return NotesState(
      notes: notes ?? this.notes,
      activeNote: clearActiveNote ? null : (activeNote ?? this.activeNote),
      searchQuery: searchQuery ?? this.searchQuery,
      sortOrder: sortOrder ?? this.sortOrder,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}
