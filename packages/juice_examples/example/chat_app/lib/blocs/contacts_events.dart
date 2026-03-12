import 'package:juice/juice.dart';

class LoadContactsEvent extends EventBase {
  LoadContactsEvent() : super(groupsToRebuild: {'contacts:list'});
}

class UpdateContactStatusEvent extends EventBase {
  final String contactId;
  final bool isOnline;
  UpdateContactStatusEvent({required this.contactId, required this.isOnline})
      : super(groupsToRebuild: {'contacts:status', 'contacts:list'});
}

class UpdateContactLastMessageEvent extends EventBase {
  final String contactId;
  final String lastMessage;
  final DateTime lastMessageTime;
  final bool incrementUnread;
  UpdateContactLastMessageEvent({
    required this.contactId,
    required this.lastMessage,
    required this.lastMessageTime,
    this.incrementUnread = false,
  }) : super(groupsToRebuild: {'contacts:list'});
}
