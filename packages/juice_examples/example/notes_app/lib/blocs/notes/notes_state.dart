import 'package:juice/juice.dart';
import '../../models/note.dart';
import '../settings/settings_state.dart';

class NotesState extends BlocState {
  final List<Note> notes;
  final String searchQuery;
  final SortOrder sortOrder;
  final ViewMode viewMode;

  const NotesState({
    this.notes = const [],
    this.searchQuery = '',
    this.sortOrder = SortOrder.updatedDesc,
    this.viewMode = ViewMode.list,
  });

  /// Active (non-trashed) notes, filtered by search and sorted with
  /// pinned notes first.
  List<Note> get filteredNotes {
    var result = notes.where((n) => !n.isTrashed).toList();

    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      result = result
          .where((n) =>
              n.title.toLowerCase().contains(query) ||
              n.body.toLowerCase().contains(query))
          .toList();
    }

    // Sort by current order
    switch (sortOrder) {
      case SortOrder.updatedDesc:
        result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case SortOrder.updatedAsc:
        result.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
      case SortOrder.titleAsc:
        result.sort((a, b) => a.title.compareTo(b.title));
      case SortOrder.titleDesc:
        result.sort((a, b) => b.title.compareTo(a.title));
    }

    // Pinned notes bubble to top, preserving relative order within each group
    final pinned = result.where((n) => n.isPinned).toList();
    final unpinned = result.where((n) => !n.isPinned).toList();
    return [...pinned, ...unpinned];
  }

  /// Trashed notes only.
  List<Note> get trashedNotes =>
      notes.where((n) => n.isTrashed).toList();

  NotesState copyWith({
    List<Note>? notes,
    String? searchQuery,
    SortOrder? sortOrder,
    ViewMode? viewMode,
  }) {
    return NotesState(
      notes: notes ?? this.notes,
      searchQuery: searchQuery ?? this.searchQuery,
      sortOrder: sortOrder ?? this.sortOrder,
      viewMode: viewMode ?? this.viewMode,
    );
  }
}
