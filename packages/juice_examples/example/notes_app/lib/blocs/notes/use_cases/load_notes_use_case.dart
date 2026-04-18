// Juice features demonstrated:
// - [BlocUseCase]: Automatic structured logging via log() and logError().
// - Multiple Hive boxes: Reads from both 'notes' and 'trash' boxes,
//   demonstrating data separation by concern.
import 'dart:convert';
import 'package:juice/juice.dart';
import 'package:juice_storage/juice_storage.dart';
import '../../../models/note.dart';
import '../../rebuild_groups.dart';
import '../notes_bloc.dart';
import '../notes_events.dart';

class LoadNotesUseCase extends BlocUseCase<NotesBloc, LoadNotesEvent> {
  @override
  Future<void> execute(LoadNotesEvent event) async {
    emitWaiting(newState: bloc.state);

    try {
      final storage = BlocScope.get<StorageBloc>();
      final notes = <Note>[];

      // Load from 'notes' box
      final noteKeys = await storage.hiveKeys('notes');
      for (final key in noteKeys) {
        final json = await storage.hiveRead<String>('notes', key);
        if (json != null) {
          notes.add(
              Note.fromJson(jsonDecode(json) as Map<String, dynamic>));
        }
      }

      // Load from 'trash' box (TTL-expired entries return null automatically)
      final trashKeys = await storage.hiveKeys('trash');
      for (final key in trashKeys) {
        final json = await storage.hiveRead<String>('trash', key);
        if (json != null) {
          notes.add(
              Note.fromJson(jsonDecode(json) as Map<String, dynamic>));
        }
      }

      log('Loaded ${notes.length} notes (${trashKeys.length} in trash)');

      emitUpdate(
        newState: bloc.state.copyWith(notes: notes),
        groupsToRebuild:
            {NotesGroups.list, NotesGroups.trash}.toStringSet(),
      );
    } catch (e, stackTrace) {
      logError(e, stackTrace);
      emitFailure(newState: bloc.state, error: e, errorStackTrace: stackTrace);
    }
  }
}
