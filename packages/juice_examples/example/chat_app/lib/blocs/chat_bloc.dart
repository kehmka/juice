import 'package:juice/juice.dart';
import 'chat_state.dart';
import 'chat_events.dart';
import 'contacts_bloc.dart';
import 'contacts_events.dart';
import 'use_cases/send_message_use_case.dart';
import 'use_cases/load_messages_use_case.dart';
import 'use_cases/receive_message_use_case.dart';
import 'use_cases/update_typing_use_case.dart';
import '../services/fake_chat_service.dart';

class ChatBloc extends JuiceBloc<ChatState> {
  final FakeChatService chatService;
  late final StreamSubscription _messageSubscription;
  late final StreamSubscription _typingSubscription;

  ChatBloc({required this.chatService})
      : super(
          const ChatState(),
          [
            () => UseCaseBuilder(
                  typeOfEvent: LoadMessagesEvent,
                  useCaseGenerator: () => LoadMessagesUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: SendMessageEvent,
                  useCaseGenerator: () => SendMessageUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: ReceiveMessageEvent,
                  useCaseGenerator: () => ReceiveMessageUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: UpdateTypingEvent,
                  useCaseGenerator: () => UpdateTypingUseCase(),
                ),
          ],
        ) {
    // Listen for incoming messages from fake service
    _messageSubscription = chatService.incomingMessages.listen((message) {
      send(ReceiveMessageEvent(message: message));

      // Also update the contact's last message
      final contactsBloc = BlocScope.get<ContactsBloc>();
      contactsBloc.send(UpdateContactLastMessageEvent(
        contactId: message.senderId,
        lastMessage: message.text,
        lastMessageTime: message.timestamp,
        incrementUnread: message.senderId != state.activeContactId,
      ));
    });

    // Listen for typing indicators
    _typingSubscription = chatService.typingIndicators.listen((contactId) {
      send(UpdateTypingEvent(
        contactId: contactId,
        isTyping: contactId.isNotEmpty,
      ));
    });
  }

  @override
  Future<void> close() async {
    await _messageSubscription.cancel();
    await _typingSubscription.cancel();
    return super.close();
  }
}
