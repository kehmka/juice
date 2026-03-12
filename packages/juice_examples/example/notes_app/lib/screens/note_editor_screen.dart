import 'dart:async';
import 'package:flutter/material.dart';
import 'package:juice/juice.dart';
import '../blocs/notes_bloc.dart';
import '../blocs/notes_events.dart';

class NoteEditorScreen extends StatefulWidget {
  final String? noteId;

  const NoteEditorScreen({super.key, this.noteId});

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  Timer? _autoSaveTimer;
  bool _hasUnsavedChanges = false;

  NotesBloc get _bloc => BlocScope.get<NotesBloc>();

  @override
  void initState() {
    super.initState();
    final note = _bloc.state.activeNote;
    _titleController = TextEditingController(text: note?.title ?? '');
    _bodyController = TextEditingController(text: note?.body ?? '');
    _titleController.addListener(_onTextChanged);
    _bodyController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    _hasUnsavedChanges = true;
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 2), _save);
  }

  void _save() {
    if (!_hasUnsavedChanges) return;
    _hasUnsavedChanges = false;
    _bloc.send(SaveNoteEvent(
      id: widget.noteId ?? _bloc.state.activeNote?.id,
      title: _titleController.text,
      body: _bodyController.text,
    ));
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    if (_hasUnsavedChanges) _save();
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.noteId != null ? 'Edit Note' : 'New Note'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _save,
          ),
          if (widget.noteId != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                _hasUnsavedChanges = false;
                _bloc.send(DeleteNoteEvent(
                    noteId: widget.noteId ?? _bloc.state.activeNote!.id));
                Navigator.of(context).pop();
              },
            ),
        ],
      ),
      body: JuiceBuilder<NotesBloc>(
        groups: const {'notes:editor'},
        builder: (context, bloc, status) {
          return Padding(
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
          );
        },
      ),
    );
  }
}
