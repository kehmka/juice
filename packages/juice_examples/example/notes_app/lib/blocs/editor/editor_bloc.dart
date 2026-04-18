// Juice features demonstrated:
// - [BlocLifecycle.leased]: EditorBloc auto-disposes when the editor screen
//   closes and the last widget lease is released. A fresh instance is created
//   each time the editor opens — no stale state.
// - [StatefulUseCaseBuilder]: AutoSaveUseCase maintains a persistent Timer
//   across events. Each keystroke cancels the old timer and starts a new
//   2-second one. Impossible with regular UseCaseBuilder (which creates a
//   new instance each time).
// - [InlineUseCaseBuilder]: UpdateContentEvent and ChangeEditorColorEvent are
//   pure state mutations — no I/O, perfect for inline lambdas.
// - [ValidationException]: ManualSaveUseCase validates that the note has
//   content before saving, throwing ValidationException with field-level errors.
import 'package:juice/juice.dart';
import '../rebuild_groups.dart';
import 'editor_state.dart';
import 'editor_events.dart';
import 'use_cases/auto_save_use_case.dart';
import 'use_cases/manual_save_use_case.dart';

class EditorBloc extends JuiceBloc<EditorState> {
  EditorBloc()
      : super(
          const EditorState(),
          [
            // Initialize editor with existing note data or blank state
            () => InlineUseCaseBuilder<EditorBloc, EditorState,
                    InitEditorEvent>(
                  typeOfEvent: InitEditorEvent,
                  handler: (ctx, event) async {
                    final note = event.existingNote;
                    if (note != null) {
                      final text = '${note.title} ${note.body}'.trim();
                      final words = text.isEmpty
                          ? 0
                          : text.split(RegExp(r'\s+')).length;
                      ctx.emit.update(
                        newState: ctx.state.copyWith(
                          noteId: note.id,
                          title: note.title,
                          body: note.body,
                          color: note.color,
                          wordCount: words,
                          charCount: text.length,
                        ),
                        groups: {EditorGroups.content, EditorGroups.stats},
                      );
                    }
                  },
                ),

            // Content changes — inline because it's a pure state update.
            // Updates word/char count and marks dirty. Only rebuilds stats.
            () => InlineUseCaseBuilder<EditorBloc, EditorState,
                    UpdateContentEvent>(
                  typeOfEvent: UpdateContentEvent,
                  handler: (ctx, event) async {
                    final title = event.title ?? ctx.state.title;
                    final body = event.body ?? ctx.state.body;
                    final text = '$title $body'.trim();
                    final words = text.isEmpty
                        ? 0
                        : text.split(RegExp(r'\s+')).length;
                    ctx.emit.update(
                      newState: ctx.state.copyWith(
                        title: event.title,
                        body: event.body,
                        isDirty: true,
                        wordCount: words,
                        charCount: text.length,
                        clearValidationError: true,
                      ),
                      groups: {EditorGroups.stats},
                    );
                  },
                ),

            // Color change — inline, trivial mutation
            () => InlineUseCaseBuilder<EditorBloc, EditorState,
                    ChangeEditorColorEvent>(
                  typeOfEvent: ChangeEditorColorEvent,
                  handler: (ctx, event) async {
                    ctx.emit.update(
                      newState: ctx.state.copyWith(
                        color: event.color,
                        isDirty: true,
                      ),
                      groups: {EditorGroups.content},
                    );
                  },
                ),

            // Auto-save with debounce — StatefulUseCaseBuilder keeps the
            // Timer alive across multiple events. This is the key difference:
            // the use case instance persists, so the Timer from the previous
            // event can be cancelled before starting a new one.
            () => StatefulUseCaseBuilder(
                  typeOfEvent: AutoSaveEvent,
                  useCaseGenerator: () => AutoSaveUseCase(),
                ),

            // Manual save — validates before saving (ValidationException)
            () => UseCaseBuilder(
                  typeOfEvent: ManualSaveEvent,
                  useCaseGenerator: () => ManualSaveUseCase(),
                ),
          ],
        );
}
