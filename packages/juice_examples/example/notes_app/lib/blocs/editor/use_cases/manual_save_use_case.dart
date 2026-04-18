// Juice features demonstrated:
// - [ValidationException]: Validates that the note has content before saving.
//   Throws with field-level error that the UI displays inline.
// - [sendAndWait]: The editor screen calls `bloc.sendAndWait(ManualSaveEvent())`
//   to await completion before navigating back, ensuring the save finishes
//   before the screen pops.
import 'dart:convert';
import 'package:juice/juice.dart';
import 'package:juice_storage/juice_storage.dart';
import '../../../models/note.dart';
import '../../rebuild_groups.dart';
import '../editor_bloc.dart';
import '../editor_events.dart';

class ManualSaveUseCase extends BlocUseCase<EditorBloc, ManualSaveEvent> {
  @override
  Future<void> execute(ManualSaveEvent event) async {
    // Validate — throws ValidationException with field-level error
    if (bloc.state.title.trim().isEmpty && bloc.state.body.trim().isEmpty) {
      emitFailure(
        newState: bloc.state.copyWith(
          validationError: 'Title or body is required',
        ),
        error: const ValidationException(
          'Note cannot be empty',
          field: 'title',
        ),
      );
      return;
    }

    emitWaiting(
      newState: bloc.state.copyWith(isSaving: true),
      groupsToRebuild: {EditorGroups.status}.toStringSet(),
    );

    try {
      final storage = BlocScope.get<StorageBloc>();
      final now = DateTime.now();
      final noteId = bloc.state.noteId.isEmpty
          ? now.millisecondsSinceEpoch.toString()
          : bloc.state.noteId;

      // Preserve createdAt for existing notes
      DateTime createdAt = now;
      if (bloc.state.noteId.isNotEmpty) {
        final existing =
            await storage.hiveRead<String>('notes', bloc.state.noteId);
        if (existing != null) {
          final parsed =
              Note.fromJson(jsonDecode(existing) as Map<String, dynamic>);
          createdAt = parsed.createdAt;
        }
      }

      final note = Note(
        id: noteId,
        title: bloc.state.title.isEmpty ? 'Untitled' : bloc.state.title,
        body: bloc.state.body,
        createdAt: createdAt,
        updatedAt: now,
        color: bloc.state.color,
      );

      await storage.hiveWrite('notes', noteId, jsonEncode(note.toJson()));

      log('Note "${note.title}" saved');

      emitUpdate(
        newState: bloc.state.copyWith(
          noteId: noteId,
          isDirty: false,
          isSaving: false,
          clearValidationError: true,
        ),
      );
    } catch (e, stackTrace) {
      logError(e, stackTrace);
      emitFailure(
        newState: bloc.state.copyWith(isSaving: false),
        error: e,
        errorStackTrace: stackTrace,
      );
    }
  }
}
