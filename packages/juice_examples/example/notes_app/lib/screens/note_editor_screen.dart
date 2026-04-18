// Juice features demonstrated:
// - [BlocLifecycle.leased]: EditorBloc is registered as leased. This screen
//   acquires a lease in initState and releases in dispose. When the screen
//   closes, the bloc auto-disposes — fresh state each time the editor opens.
// - [sendAndWait]: Save-and-close awaits the ManualSaveEvent before popping
//   the screen, ensuring the save completes before navigation.
// - [Multiple JuiceBuilder groups]: Three JuiceBuilder instances each listen
//   to different rebuild groups:
//   - editor:status — save indicator (spinner / dirty dot / checkmark)
//   - editor:content — validation error display
//   - editor:stats — word and character count bar
//   Typing updates word count without rebuilding the save indicator.
// - [ValidationException]: ManualSaveUseCase validates non-empty content.
//   The validation error appears inline via the content JuiceBuilder.
import 'package:juice/juice.dart';
import '../blocs/editor/editor_bloc.dart';
import '../blocs/editor/editor_events.dart';
import '../blocs/notes/notes_bloc.dart';
import '../blocs/notes/notes_events.dart';
import '../blocs/rebuild_groups.dart';
import '../models/note.dart';

class NoteEditorScreen extends StatefulWidget {
  final Note? existingNote;

  const NoteEditorScreen({super.key, this.existingNote});

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late final BlocLease<EditorBloc> _lease;
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;

  EditorBloc get _bloc => _lease.bloc;

  @override
  void initState() {
    super.initState();
    // Acquire a lease — EditorBloc auto-disposes when we release it
    _lease = BlocScope.lease<EditorBloc>();

    _titleController = TextEditingController(
      text: widget.existingNote?.title ?? '',
    );
    _bodyController = TextEditingController(
      text: widget.existingNote?.body ?? '',
    );

    // Initialize editor with existing note data (if editing)
    _bloc.send(InitEditorEvent(existingNote: widget.existingNote));

    _titleController.addListener(_onContentChanged);
    _bodyController.addListener(_onContentChanged);
  }

  void _onContentChanged() {
    // Update content state (rebuilds stats group only)
    _bloc.send(UpdateContentEvent(
      title: _titleController.text,
      body: _bodyController.text,
    ));
    // Trigger auto-save debounce (rebuilds status group only)
    _bloc.send(AutoSaveEvent());
  }

  /// Save and close — uses sendAndWait to ensure save completes before pop
  Future<void> _saveAndClose() async {
    try {
      final status = await _bloc.sendAndWait(ManualSaveEvent());
      if (!mounted) return;

      if (status is FailureStatus) {
        // Validation failed — don't pop, error shows via content JuiceBuilder
        return;
      }
    } catch (_) {
      // Bloc may have been disposed during save — save through NotesBloc
      if (!mounted) return;
    }
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    // Read editor state before releasing the lease (bloc disposes after)
    final editorState = _bloc.state;
    final notesBloc = BlocScope.get<NotesBloc>();

    // If there are unsaved changes, save through NotesBloc (permanent)
    // so the note persists even though EditorBloc is about to dispose
    if (editorState.isDirty &&
        (editorState.title.trim().isNotEmpty ||
            editorState.body.trim().isNotEmpty)) {
      notesBloc.send(SaveNoteEvent(
        id: editorState.noteId.isEmpty ? null : editorState.noteId,
        title: editorState.title,
        body: editorState.body,
        color: editorState.color,
      ));
    }

    // Reload notes from Hive to pick up any auto-saves from this session
    notesBloc.send(LoadNotesEvent());

    _titleController.dispose();
    _bodyController.dispose();
    // Release the lease — EditorBloc auto-disposes (BlocLifecycle.leased)
    _lease.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existingNote != null ? 'Edit Note' : 'New Note',
        ),
        actions: [
          // JuiceBuilder #1: editor:status — save indicator
          // Only rebuilds when save status changes (saving/dirty/saved)
          JuiceBuilder<EditorBloc>(
            groups: {EditorGroups.status}.toStringSet(),
            builder: (context, bloc, status) {
              if (bloc.state.isSaving) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              if (bloc.state.isDirty) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.circle, size: 10, color: Colors.orange),
                );
              }
              if (bloc.state.noteId.isNotEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.check_circle, size: 20, color: Colors.green),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          // Color picker button
          IconButton(
            icon: const Icon(Icons.palette_outlined),
            onPressed: () => _showColorPicker(context),
          ),
          // Save and close — sendAndWait
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Save & close',
            onPressed: _saveAndClose,
          ),
        ],
      ),
      body: Column(
        children: [
          // JuiceBuilder #2: editor:content — validation error
          // Only rebuilds when validation state changes, not on every keystroke
          JuiceBuilder<EditorBloc>(
            groups: {EditorGroups.content}.toStringSet(),
            builder: (context, bloc, status) {
              if (bloc.state.validationError != null) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  color: Colors.red[50],
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.red[700]),
                      const SizedBox(width: 8),
                      Text(
                        bloc.state.validationError!,
                        style: TextStyle(color: Colors.red[700]),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _titleController,
                    style: Theme.of(context).textTheme.headlineSmall,
                    decoration: const InputDecoration(
                      hintText: 'Title',
                      border: InputBorder.none,
                    ),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const Divider(),
                  Expanded(
                    child: TextField(
                      controller: _bodyController,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(
                        hintText: 'Start writing...',
                        border: InputBorder.none,
                      ),
                      textCapitalization: TextCapitalization.sentences,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // JuiceBuilder #3: editor:stats — word and character count
          // Typing updates this without rebuilding the save indicator or
          // validation error display. Granular rebuild control in action.
          JuiceBuilder<EditorBloc>(
            groups: {EditorGroups.stats}.toStringSet(),
            builder: (context, bloc, status) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Colors.grey[300]!),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '${bloc.state.wordCount} words',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(width: 16),
                    Text(
                      '${bloc.state.charCount} chars',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showColorPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Note color',
                style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              children: NoteColor.values.map((color) {
                final colorValue = _noteColorToColor(color);
                return GestureDetector(
                  onTap: () {
                    _bloc.send(ChangeEditorColorEvent(color: color));
                    Navigator.pop(ctx);
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colorValue ?? Colors.grey[200],
                      shape: BoxShape.circle,
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
