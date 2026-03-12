import 'package:juice/juice.dart';
import '../models/message.dart';

class ChatState extends BlocState {
  final List<Message> messages;
  final String? activeContactId;
  final bool isTyping;
  final bool peerIsTyping;

  const ChatState({
    this.messages = const [],
    this.activeContactId,
    this.isTyping = false,
    this.peerIsTyping = false,
  });

  List<Message> get activeMessages {
    if (activeContactId == null) return [];
    return messages
        .where((m) =>
            m.senderId == activeContactId ||
            m.receiverId == activeContactId)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  ChatState copyWith({
    List<Message>? messages,
    String? activeContactId,
    bool? isTyping,
    bool? peerIsTyping,
    bool clearActiveContact = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      activeContactId:
          clearActiveContact ? null : (activeContactId ?? this.activeContactId),
      isTyping: isTyping ?? this.isTyping,
      peerIsTyping: peerIsTyping ?? this.peerIsTyping,
    );
  }
}
