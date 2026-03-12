import 'dart:convert';
import 'package:juice/juice.dart';
import 'package:juice_storage/juice_storage.dart';
import '../chat_bloc.dart';
import '../chat_events.dart';
import '../../models/message.dart';

class LoadMessagesUseCase extends UseCase<ChatBloc, LoadMessagesEvent> {
  @override
  Future<void> execute(LoadMessagesEvent event) async {
    emitWaiting();

    final storageBloc = BlocScope.get<StorageBloc>();
    final key = 'messages_${event.contactId}';
    final json = await storageBloc.hiveRead<String>('chat', key);

    List<Message> messages = [];
    if (json != null) {
      final list = jsonDecode(json) as List<dynamic>;
      messages = list
          .map((e) => Message.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    emitUpdate(
      newState: bloc.state.copyWith(
        messages: messages,
        activeContactId: event.contactId,
        peerIsTyping: false,
      ),
    );
  }
}
