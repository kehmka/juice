import 'package:flutter/material.dart';
import 'package:juice/juice.dart';
import 'package:juice_storage/juice_storage.dart';
import 'blocs/notes_bloc.dart';
import 'screens/notes_list_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Register StorageBloc for Hive + SharedPreferences
  BlocScope.register<StorageBloc>(
    () => StorageBloc(
      config: const StorageConfig(
        hiveBoxesToOpen: ['notes'],
      ),
    ),
  );

  // Initialize storage before app starts
  final storageBloc = BlocScope.get<StorageBloc>();
  await storageBloc.initialize();

  // Register NotesBloc
  BlocScope.register<NotesBloc>(() => NotesBloc());

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
