import 'package:juice/juice.dart';
import '../../models/note.dart';

class EditorState extends BlocState {
  final String noteId;
  final String title;
  final String body;
  final NoteColor color;
  final bool isDirty;
  final bool isSaving;
  final String? validationError;
  final int wordCount;
  final int charCount;

  const EditorState({
    this.noteId = '',
    this.title = '',
    this.body = '',
    this.color = NoteColor.none,
    this.isDirty = false,
    this.isSaving = false,
    this.validationError,
    this.wordCount = 0,
    this.charCount = 0,
  });

  EditorState copyWith({
    String? noteId,
    String? title,
    String? body,
    NoteColor? color,
    bool? isDirty,
    bool? isSaving,
    String? validationError,
    bool clearValidationError = false,
    int? wordCount,
    int? charCount,
  }) {
    return EditorState(
      noteId: noteId ?? this.noteId,
      title: title ?? this.title,
      body: body ?? this.body,
      color: color ?? this.color,
      isDirty: isDirty ?? this.isDirty,
      isSaving: isSaving ?? this.isSaving,
      validationError: clearValidationError
          ? null
          : (validationError ?? this.validationError),
      wordCount: wordCount ?? this.wordCount,
      charCount: charCount ?? this.charCount,
    );
  }
}
