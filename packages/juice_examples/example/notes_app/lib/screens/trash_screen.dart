// Juice features demonstrated:
// - [CancellableEvent]: EmptyTrashEvent is a CancellableEvent. The user
//   can cancel the batch deletion mid-operation. The use case checks
//   [isCancelled] between each delete and stops gracefully.
// - [sendCancellable]: Returns the event instance so the UI can call
//   event.cancel() from a button press.
// - [status.when()]: Exhaustive pattern matching for waiting (emptying
//   in progress), canceling (user cancelled), failure, and success states.
// - [RebuildGroup]: Only rebuilds on notes:trash group changes.
import 'package:juice/juice.dart';
import '../blocs/notes/notes_bloc.dart';
import '../blocs/notes/notes_events.dart';
import '../blocs/rebuild_groups.dart';
import '../models/note.dart';

class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  EmptyTrashEvent? _activeEmptyTrash;

  @override
  Widget build(BuildContext context) {
    return JuiceBuilder<NotesBloc>(
      groups: {NotesGroups.trash}.toStringSet(),
      builder: (context, bloc, status) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Trash'),
            actions: [
              if (bloc.state.trashedNotes.isNotEmpty)
                status is WaitingStatus
                    ? TextButton(
                        onPressed: () {
                          _activeEmptyTrash?.cancel();
                          setState(() => _activeEmptyTrash = null);
                        },
                        child: const Text('Cancel'),
                      )
                    : TextButton.icon(
                        icon: const Icon(Icons.delete_forever),
                        label: const Text('Empty Trash'),
                        onPressed: () => _emptyTrash(context, bloc),
                      ),
            ],
          ),
          body: status.when(
            waiting: (state, _, __) => const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Emptying trash...'),
                ],
              ),
            ),
            canceling: (state, _, __) => _buildTrashList(context, bloc),
            failure: (state, _, __) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                  const SizedBox(height: 12),
                  const Text('Something went wrong'),
                ],
              ),
            ),
            updating: (state, _, __) => _buildTrashList(context, bloc),
          ),
        );
      },
    );
  }

  void _emptyTrash(BuildContext context, NotesBloc bloc) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Empty Trash'),
        content: Text(
          'Permanently delete ${bloc.state.trashedNotes.length} note(s)? '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              // sendCancellable returns the event — keep a reference
              // so we can cancel it from the AppBar button
              setState(() {
                _activeEmptyTrash =
                    bloc.sendCancellable(EmptyTrashEvent());
              });
            },
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
  }

  Widget _buildTrashList(BuildContext context, NotesBloc bloc) {
    final trashedNotes = bloc.state.trashedNotes;

    if (trashedNotes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Trash is empty',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: trashedNotes.length,
      itemBuilder: (context, index) {
        final note = trashedNotes[index];
        return _trashCard(context, bloc, note);
      },
    );
  }

  Widget _trashCard(BuildContext context, NotesBloc bloc, Note note) {
    return Card(
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.restore),
              tooltip: 'Restore',
              onPressed: () =>
                  bloc.send(RestoreFromTrashEvent(noteId: note.id)),
            ),
            IconButton(
              icon: const Icon(Icons.delete_forever),
              tooltip: 'Delete permanently',
              onPressed: () => _confirmPermanentDelete(context, bloc, note),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmPermanentDelete(
      BuildContext context, NotesBloc bloc, Note note) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Permanently'),
        content: Text('Delete "${note.title}" forever?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              bloc.send(PermanentDeleteEvent(noteId: note.id));
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
