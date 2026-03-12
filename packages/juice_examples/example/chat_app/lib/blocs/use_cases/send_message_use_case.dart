import 'package:juice/juice.dart';
import '../chat_bloc.dart';
import '../chat_events.dart';
import '../../models/message.dart';

class SendMessageUseCase extends UseCase<ChatBloc, SendMessageEvent> {
  @override
  Future<void> execute(SendMessageEvent event) async {
    final message = Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      senderId: 'me',
      receiverId: event.receiverId,
      text: event.text,
      timestamp: DateTime.now(),
    );

    final updatedMessages = [...bloc.state.messages, message];
    emitUpdate(
      newState: bloc.state.copyWith(messages: updatedMessages),
    );

    // Notify the fake chat service so it can auto-reply
    bloc.chatService.sendMessage(message);
  }
}
