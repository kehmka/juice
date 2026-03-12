import 'package:juice/juice.dart';
import 'notes_state.dart';
import 'notes_events.dart';
import 'use_cases/load_notes_use_case.dart';
import 'use_cases/save_note_use_case.dart';
import 'use_cases/delete_note_use_case.dart';
import 'use_cases/search_notes_use_case.dart';

class NotesBloc extends JuiceBloc<NotesState> {
  NotesBloc()
      : super(
          const NotesState(),
          [
            () => UseCaseBuilder(
                  typeOfEvent: LoadNotesEvent,
                  useCaseGenerator: () => LoadNotesUseCase(),
                  initialEventBuilder: () => LoadNotesEvent(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: SaveNoteEvent,
                  useCaseGenerator: () => SaveNoteUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: DeleteNoteEvent,
                  useCaseGenerator: () => DeleteNoteUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: SearchNotesEvent,
                  useCaseGenerator: () => SearchNotesUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: SelectNoteEvent,
                  useCaseGenerator: () => SelectNoteUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: ChangeSortOrderEvent,
                  useCaseGenerator: () => ChangeSortOrderUseCase(),
                ),
          ],
        );
}
