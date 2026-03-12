import 'package:flutter/material.dart';
import 'package:juice/juice.dart';
import '../blocs/notes_bloc.dart';
import '../blocs/notes_state.dart';
import '../blocs/notes_events.dart';
import 'note_editor_screen.dart';

class NotesListScreen extends StatelessJuiceWidget<NotesBloc> {
  NotesListScreen({super.key})
      : super(groups: const {'notes:list', 'notes:search'});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final state = bloc.state;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes'),
        actions: [
          PopupMenuButton<NotesSortOrder>(
            icon: const Icon(Icons.sort),
            onSelected: (order) =>
                bloc.send(ChangeSortOrderEvent(sortOrder: order)),
            itemBuilder: (_) => [
              _sortMenuItem('Latest First', NotesSortOrder.updatedDesc, state),
              _sortMenuItem('Oldest First', NotesSortOrder.updatedAsc, state),
              _sortMenuItem('Title A-Z', NotesSortOrder.titleAsc, state),
              _sortMenuItem('Title Z-A', NotesSortOrder.titleDesc, state),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search notes...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
              ),
              onChanged: (query) =>
                  bloc.send(SearchNotesEvent(query: query)),
            ),
          ),
          Expanded(child: _buildContent(context, state, status)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(context, null),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, NotesState state, StreamStatus status) {
    if (status is WaitingStatus) {
      return const Center(child: CircularProgressIndicator());
    }

    final notes = state.filteredNotes;
    if (notes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.note_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              state.searchQuery.isNotEmpty
                  ? 'No notes match your search'
                  : 'No notes yet — tap + to create one',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: notes.length,
      itemBuilder: (context, index) {
        final note = notes[index];
        return Dismissible(
          key: ValueKey(note.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: Colors.red,
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (_) =>
              bloc.send(DeleteNoteEvent(noteId: note.id)),
          child: Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(
                note.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                note.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                _formatDate(note.updatedAt),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              onTap: () => _openEditor(context, note.id),
            ),
          ),
        );
      },
    );
  }

  void _openEditor(BuildContext context, String? noteId) {
    if (noteId != null) {
      bloc.send(SelectNoteEvent(noteId: noteId));
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: noteId)),
    );
  }

  PopupMenuEntry<NotesSortOrder> _sortMenuItem(
      String label, NotesSortOrder order, NotesState state) {
    return PopupMenuItem(
      value: order,
      child: Row(
        children: [
          if (state.sortOrder == order)
            const Icon(Icons.check, size: 18)
          else
            const SizedBox(width: 18),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.month}/${date.day}/${date.year}';
  }

  @override
  Widget close(BuildContext context) => const SizedBox.shrink();
}
