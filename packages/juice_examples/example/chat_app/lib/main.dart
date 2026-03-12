import 'package:flutter/material.dart';
import 'package:juice/juice.dart';
import 'package:juice_storage/juice_storage.dart';
import 'blocs/chat_bloc.dart';
import 'blocs/contacts_bloc.dart';
import 'services/fake_chat_service.dart';
import 'screens/conversations_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Shared fake chat service
  final chatService = FakeChatService();

  // Register StorageBloc for message persistence
  BlocScope.register<StorageBloc>(
    () => StorageBloc(
      config: const StorageConfig(hiveBoxesToOpen: ['chat']),
    ),
  );
  final storageBloc = BlocScope.get<StorageBloc>();
  await storageBloc.initialize();

  // Register blocs
  BlocScope.register<ContactsBloc>(
    () => ContactsBloc(chatService: chatService),
  );
  BlocScope.register<ChatBloc>(
    () => ChatBloc(chatService: chatService),
  );

  runApp(const ChatApp());
}

class ChatApp extends StatelessWidget {
  const ChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Juice Chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: ConversationsScreen(),
    );
  }
}
