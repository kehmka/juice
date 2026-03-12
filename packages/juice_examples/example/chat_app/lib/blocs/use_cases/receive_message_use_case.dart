import 'dart:convert';
import 'package:juice/juice.dart';
import 'package:juice_storage/juice_storage.dart';
import '../chat_bloc.dart';
import '../chat_events.dart';

class ReceiveMessageUseCase extends UseCase<ChatBloc, ReceiveMessageEvent> {
  @override
  Future<void> execute(ReceiveMessageEvent event) async {
    final updatedMessages = [...bloc.state.messages, event.message];
    emitUpdate(
      newState: bloc.state.copyWith(
        messages: updatedMessages,
        peerIsTyping: false,
      ),
    );

    // Persist messages to storage
    final storageBloc = BlocScope.get<StorageBloc>();
    final contactId = event.message.senderId == 'me'
        ? event.message.receiverId
        : event.message.senderId;
    final key = 'messages_$contactId';
    final json = jsonEncode(
        updatedMessages.map((m) => m.toJson()).toList());
    await storageBloc.hiveWrite<String>('chat', key, json);
  }
}
