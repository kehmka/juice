import 'package:juice/juice.dart';
import '../../models/note.dart';
import '../rebuild_groups.dart';

class InitEditorEvent extends EventBase {
  final Note? existingNote;

  InitEditorEvent({this.existingNote})
      : super(
            groupsToRebuild:
                {EditorGroups.content, EditorGroups.stats}.toStringSet());
}

class UpdateContentEvent extends EventBase {
  final String? title;
  final String? body;

  UpdateContentEvent({this.title, this.body})
      : super(groupsToRebuild: {EditorGroups.stats}.toStringSet());
  // Only rebuilds stats widget (word count), not the whole editor
}

class AutoSaveEvent extends EventBase {
  AutoSaveEvent()
      : super(groupsToRebuild: {EditorGroups.status}.toStringSet());
  // Only rebuilds save status indicator
}

class ManualSaveEvent extends EventBase {
  ManualSaveEvent()
      : super(
            groupsToRebuild:
                {EditorGroups.status, EditorGroups.content}.toStringSet());
}

class ChangeEditorColorEvent extends EventBase {
  final NoteColor color;

  ChangeEditorColorEvent({required this.color})
      : super(groupsToRebuild: {EditorGroups.content}.toStringSet());
}
