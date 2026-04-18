// Juice features demonstrated:
// - [BlocLifecycle.permanent]: StorageBloc, NotesBloc, and SettingsBloc
//   live for the entire app lifetime — they hold app-level state.
// - [BlocLifecycle.leased]: EditorBloc auto-disposes when the editor screen
//   closes and releases its lease. Fresh instance each time the editor opens.
// - Multiple Hive boxes: 'notes' and 'trash' separate active notes from
//   soft-deleted notes, each with independent key spaces.
// - [enableLeakDetection]: Debug-mode tooling that tracks bloc creations
//   and lease acquisitions, flagging unreleased leases.
import 'package:flutter/foundation.dart';
import 'package:juice/juice.dart';
import 'package:juice_storage/juice_storage.dart';
import 'blocs/notes/notes_bloc.dart';
import 'blocs/settings/settings_bloc.dart';
import 'blocs/editor/editor_bloc.dart';
import 'screens/notes_list_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Debug-mode leak detection — tracks unreleased bloc leases
  if (kDebugMode) {
    BlocScope.enableLeakDetection();
  }

  // StorageBloc: permanent — opens both 'notes' and 'trash' Hive boxes
  BlocScope.register<StorageBloc>(
    () => StorageBloc(
      config: const StorageConfig(
        hiveBoxesToOpen: ['notes', 'trash'],
      ),
    ),
    lifecycle: BlocLifecycle.permanent,
  );

  // Initialize storage before registering blocs that depend on it
  final storageBloc = BlocScope.get<StorageBloc>();
  await storageBloc.initialize();

  // SettingsBloc: permanent — persists sort/view preferences across app
  BlocScope.register<SettingsBloc>(
    () => SettingsBloc(),
    lifecycle: BlocLifecycle.permanent,
  );

  // NotesBloc: permanent — holds all notes and trash state
  BlocScope.register<NotesBloc>(
    () => NotesBloc(),
    lifecycle: BlocLifecycle.permanent,
  );

  // EditorBloc: leased — auto-disposes when editor screen releases its lease.
  // Each editor session gets a fresh instance with clean state.
  BlocScope.register<EditorBloc>(
    () => EditorBloc(),
    lifecycle: BlocLifecycle.leased,
  );

  runApp(const NotesApp());
}

class NotesApp extends StatelessWidget {
  const NotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Juice Notes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.amber,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.amber,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: NotesListScreen(),
    );
  }
}
