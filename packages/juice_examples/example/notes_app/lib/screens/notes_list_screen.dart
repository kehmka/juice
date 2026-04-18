// Juice features demonstrated:
// - [StatelessJuiceWidget2]: Observes two blocs (NotesBloc + SettingsBloc)
//   in a single widget. Grid/list toggle comes from SettingsBloc,
//   note data from NotesBloc — no manual stream merging.
// - [status.when()]: Exhaustive pattern matching on StreamStatus for
//   loading, error, and content states.
// - [RebuildGroup]: Only rebuilds when notes:list, notes:search, or
//   settings:viewMode groups emit — not on trash or editor changes.
import 'package:juice/juice.dart';
import '../blocs/notes/notes_bloc.dart';
import '../blocs/notes/notes_events.dart';
import '../blocs/rebuild_groups.dart';
import '../blocs/settings/settings_bloc.dart';
import '../blocs/settings/settings_events.dart';
import '../blocs/settings/settings_state.dart';
import '../models/note.dart';
import 'note_editor_screen.dart';
import 'trash_screen.dart';

class NotesListScreen
    extends StatelessJuiceWidget2<NotesBloc, SettingsBloc> {
  NotesListScreen({super.key})
      : super(
          groups: {
            NotesGroups.list,
            NotesGroups.search,
            SettingsGroups.viewMode,
          }.toStringSet(),
        );

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes'),
        actions: [
          IconButton(
            icon: Icon(
              bloc2.state.viewMode == ViewMode.grid
                  ? Icons.view_list
                  : Icons.grid_view,
            ),
            tooltip: bloc2.state.viewMode == ViewMode.grid
                ? 'List view'
                : 'Grid view',
            onPressed: () => bloc2.send(ToggleViewModeEvent()),
          ),
          PopupMenuButton<SortOrder>(
            icon: const Icon(Icons.sort),
            onSelected: (order) =>
                bloc2.send(ChangeSortOrderEvent(sortOrder: order)),
            itemBuilder: (_) => [
              _sortMenuItem('Latest First', SortOrder.updatedDesc),
              _sortMenuItem('Oldest First', SortOrder.updatedAsc),
              _sortMenuItem('Title A-Z', SortOrder.titleAsc),
              _sortMenuItem('Title Z-A', SortOrder.titleDesc),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Trash',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TrashScreen()),
            ),
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
                  bloc1.send(SearchNotesEvent(query: query)),
            ),
          ),
          Expanded(
            child: status.when(
              waiting: (state, _, __) =>
                  const Center(child: CircularProgressIndicator()),
              failure: (state, _, event) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline,
                        size: 48, color: Colors.red[300]),
                    const SizedBox(height: 12),
                    const Text('Failed to load notes'),
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: () => bloc1.send(LoadNotesEvent()),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              canceling: (state, _, __) => _buildNotesList(context),
              updating: (state, _, __) => _buildNotesList(context),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(context, null),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildNotesList(BuildContext context) {
    final notes = bloc1.state.filteredNotes;

    if (notes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.note_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              bloc1.state.searchQuery.isNotEmpty
                  ? 'No notes match your search'
                  : 'No notes yet \u2014 tap + to create one',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
          ],
        ),
      );
    }

    if (bloc2.state.viewMode == ViewMode.grid) {
      return _buildGrid(context, notes);
    }
    return _buildList(context, notes);
  }

  Widget _buildList(BuildContext context, List<Note> notes) {
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
          onDismissed: (_) {
            bloc1.send(MoveToTrashEvent(noteId: note.id));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('"${note.title}" moved to trash'),
                action: SnackBarAction(
                  label: 'Undo',
                  onPressed: () =>
                      bloc1.send(RestoreFromTrashEvent(noteId: note.id)),
                ),
              ),
            );
          },
          child: _noteCard(context, note),
        );
      },
    );
  }

  Widget _buildGrid(BuildContext context, List<Note> notes) {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.0,
      ),
      itemCount: notes.length,
      itemBuilder: (context, index) => _noteCard(context, notes[index]),
    );
  }

  Widget _noteCard(BuildContext context, Note note) {
    final colorValue = _noteColorToColor(note.color);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openEditor(context, note),
        onLongPress: () => _showColorPicker(context, note),
        child: Container(
          decoration: colorValue != null
              ? BoxDecoration(
                  border: Border(
                    left: BorderSide(color: colorValue, width: 4),
                  ),
                )
              : null,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (note.isPinned)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.push_pin,
                          size: 14, color: Colors.grey[600]),
                    ),
                  Expanded(
                    child: Text(
                      note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    _formatDate(note.updatedAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                note.body,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openEditor(BuildContext context, Note? note) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NoteEditorScreen(existingNote: note)),
    );
  }

  void _showColorPicker(BuildContext context, Note note) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Note color',
                    style: Theme.of(ctx).textTheme.titleMedium),
                TextButton(
                  onPressed: () {
                    bloc1.send(TogglePinEvent(noteId: note.id));
                    Navigator.pop(ctx);
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(note.isPinned
                          ? Icons.push_pin
                          : Icons.push_pin_outlined),
                      const SizedBox(width: 4),
                      Text(note.isPinned ? 'Unpin' : 'Pin'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              children: NoteColor.values.map((color) {
                final colorValue = _noteColorToColor(color);
                final isSelected = note.color == color;
                return GestureDetector(
                  onTap: () {
                    bloc1.send(
                      ChangeNoteColorEvent(noteId: note.id, color: color),
                    );
                    Navigator.pop(ctx);
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colorValue ?? Colors.grey[200],
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(
                              color: Theme.of(ctx).colorScheme.primary,
                              width: 3)
                          : null,
                    ),
                    child: color == NoteColor.none
                        ? Icon(Icons.format_color_reset,
                            size: 20, color: Colors.grey[600])
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  PopupMenuEntry<SortOrder> _sortMenuItem(String label, SortOrder order) {
    return PopupMenuItem(
      value: order,
      child: Row(
        children: [
          if (bloc2.state.sortOrder == order)
            const Icon(Icons.check, size: 18)
          else
            const SizedBox(width: 18),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  @override
  Widget close(BuildContext context) => const SizedBox.shrink();
}

Color? _noteColorToColor(NoteColor color) {
  switch (color) {
    case NoteColor.none:
      return null;
    case NoteColor.red:
      return Colors.red[200];
    case NoteColor.orange:
      return Colors.orange[200];
    case NoteColor.yellow:
      return Colors.yellow[200];
    case NoteColor.green:
      return Colors.green[200];
    case NoteColor.blue:
      return Colors.blue[200];
    case NoteColor.purple:
      return Colors.purple[200];
  }
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
