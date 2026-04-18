import 'package:juice/juice.dart';
import '../../models/note.dart';
import '../rebuild_groups.dart';
import '../settings/settings_state.dart';

class LoadNotesEvent extends EventBase {
  LoadNotesEvent()
      : super(
            groupsToRebuild:
                {NotesGroups.list, NotesGroups.trash}.toStringSet());
}

class SaveNoteEvent extends EventBase {
  final String? id;
  final String title;
  final String body;
  final NoteColor? color;
  final bool? isPinned;

  SaveNoteEvent({
    this.id,
    required this.title,
    required this.body,
    this.color,
    this.isPinned,
  }) : super(groupsToRebuild: {NotesGroups.list}.toStringSet());
}

class SearchNotesEvent extends EventBase {
  final String query;

  SearchNotesEvent({required this.query})
      : super(
            groupsToRebuild:
                {NotesGroups.search, NotesGroups.list}.toStringSet());
}

class TogglePinEvent extends EventBase {
  final String noteId;

  TogglePinEvent({required this.noteId})
      : super(groupsToRebuild: {NotesGroups.list}.toStringSet());
}

class ChangeNoteColorEvent extends EventBase {
  final String noteId;
  final NoteColor color;

  ChangeNoteColorEvent({required this.noteId, required this.color})
      : super(groupsToRebuild: {NotesGroups.list}.toStringSet());
}

class MoveToTrashEvent extends EventBase {
  final String noteId;

  MoveToTrashEvent({required this.noteId})
      : super(groupsToRebuild: {NotesGroups.list}.toStringSet());
}

class RestoreFromTrashEvent extends EventBase {
  final String noteId;

  RestoreFromTrashEvent({required this.noteId})
      : super(
            groupsToRebuild:
                {NotesGroups.trash, NotesGroups.list}.toStringSet());
}

/// Juice feature: [CancellableEvent] — user can cancel batch deletion
/// of all trashed notes. The use case checks [isCancelled] between each
/// delete operation.
class EmptyTrashEvent extends CancellableEvent {
  EmptyTrashEvent();
}

class PermanentDeleteEvent extends EventBase {
  final String noteId;

  PermanentDeleteEvent({required this.noteId})
      : super(groupsToRebuild: {NotesGroups.trash}.toStringSet());
}

/// Dispatched by [StateRelay] from [SettingsBloc] — no manual wiring needed.
class SettingsChangedEvent extends EventBase {
  final SortOrder sortOrder;
  final ViewMode viewMode;

  SettingsChangedEvent({required this.sortOrder, required this.viewMode})
      : super(groupsToRebuild: {NotesGroups.list}.toStringSet());
}
