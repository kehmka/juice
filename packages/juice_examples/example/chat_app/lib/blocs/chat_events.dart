import 'package:juice/juice.dart';
import '../models/message.dart';

class LoadMessagesEvent extends EventBase {
  final String contactId;
  LoadMessagesEvent({required this.contactId})
      : super(groupsToRebuild: {'chat:messages'});
}

class SendMessageEvent extends EventBase {
  final String text;
  final String receiverId;
  SendMessageEvent({required this.text, required this.receiverId})
      : super(groupsToRebuild: {'chat:messages'});
}

class ReceiveMessageEvent extends EventBase {
  final Message message;
  ReceiveMessageEvent({required this.message})
      : super(groupsToRebuild: {'chat:messages'});
}

class UpdateTypingEvent extends EventBase {
  final String contactId;
  final bool isTyping;
  UpdateTypingEvent({required this.contactId, required this.isTyping})
      : super(groupsToRebuild: {'chat:typing'});
}
