# notes_app

Offline-first notes app showcasing the strongest parts of the Juice ecosystem.

## Why Start Here

This is the recommended first example for evaluating Juice because it demonstrates:

- `StorageBloc` for persistence across multiple boxes
- `BlocLifecycle.permanent` for app-wide state
- `BlocLifecycle.leased` for editor-session state
- rebuild groups for targeted UI updates
- `StatefulUseCaseBuilder` for debounced autosave
- a `Reaction` for cross-bloc coordination: the notes bloc reacts to the settings bloc's state

## Run

```bash
flutter run
```

## Structure

- `NotesBloc`: persistent notes and trash state
- `EditorBloc`: leased editing session with autosave
- `SettingsBloc`: persisted view/sort preferences; `NotesBloc` reacts to them

This app is intentionally closer to a production-style reference than the repository-root showcase app.
