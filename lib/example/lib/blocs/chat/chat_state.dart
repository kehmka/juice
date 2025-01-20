import 'package:juice/juice.dart';

class ChatState extends BlocState {
  final List<String> messages;
  final String lastError;
  final bool isConnected;

  ChatState({
    required this.messages,
    required this.lastError,
    required this.isConnected,
  });

  ChatState copyWith(
      {List<String>? messages, String? lastError, bool? isConnected}) {
    return ChatState(
      messages: messages ?? this.messages,
      lastError: lastError ?? this.lastError,
      isConnected: isConnected ?? this.isConnected,
    );
  }
}
