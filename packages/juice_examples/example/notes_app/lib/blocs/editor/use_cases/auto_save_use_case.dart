// Juice feature: [StatefulUseCaseBuilder] — this use case maintains a Timer
// instance across multiple event dispatches. When the user types, each
// keystroke dispatches AutoSaveEvent. The previous timer is cancelled and
// a new 2-second timer starts. When it fires, it saves to Hive.
//
// With a regular UseCaseBuilder, a new use case instance is created each
// time, so there's no way to cancel the previous timer. StatefulUseCaseBuilder
// reuses the same instance, making debounce trivial.
import 'dart:convert';
import 'package:juice/juice.dart';
import 'package:juice_storage/juice_storage.dart';
import '../../../models/note.dart';
import '../../rebuild_groups.dart';
import '../editor_bloc.dart';
import '../editor_events.dart';

class AutoSaveUseCase extends BlocUseCase<EditorBloc, AutoSaveEvent> {
  Timer? _debounceTimer;

  @override
  Future<void> execute(AutoSaveEvent event) async {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 2), () {
      _performSave();
    });
  }

  Future<void> _performSave() async {
    if (!bloc.state.isDirty) return;
    if (bloc.state.title.trim().isEmpty && bloc.state.body.trim().isEmpty) {
      return;
    }

    log('Auto-saving note');
    emitUpdate(
      newState: bloc.state.copyWith(isSaving: true),
      groupsToRebuild: {EditorGroups.status}.toStringSet(),
    );

    try {
      final storage = BlocScope.get<StorageBloc>();
      final now = DateTime.now();
      final noteId = bloc.state.noteId.isEmpty
          ? now.millisecondsSinceEpoch.toString()
          : bloc.state.noteId;

      final note = Note(
        id: noteId,
        title: bloc.state.title.isEmpty ? 'Untitled' : bloc.state.title,
        body: bloc.state.body,
        createdAt: now,
        updatedAt: now,
        color: bloc.state.color,
      );

      await storage.hiveWrite('notes', noteId, jsonEncode(note.toJson()));

      emitUpdate(
        newState: bloc.state.copyWith(
          noteId: noteId,
          isDirty: false,
          isSaving: false,
        ),
        groupsToRebuild: {EditorGroups.status}.toStringSet(),
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

  @override
  void close() {
    _debounceTimer?.cancel();
    super.close();
  }
}
