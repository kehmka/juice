import 'package:juice/juice.dart';
import '../contacts_bloc.dart';
import '../contacts_events.dart';

class LoadContactsUseCase extends UseCase<ContactsBloc, LoadContactsEvent> {
  @override
  Future<void> execute(LoadContactsEvent event) async {
    emitWaiting(newState: bloc.state.copyWith(isLoading: true));

    final contacts = bloc.chatService.getContacts();

    emitUpdate(
      newState: bloc.state.copyWith(contacts: contacts, isLoading: false),
    );
  }
}

class UpdateContactStatusUseCase
    extends UseCase<ContactsBloc, UpdateContactStatusEvent> {
  @override
  Future<void> execute(UpdateContactStatusEvent event) async {
    final updatedContacts = bloc.state.contacts.map((c) {
      if (c.id == event.contactId) {
        return c.copyWith(isOnline: event.isOnline);
      }
      return c;
    }).toList();

    emitUpdate(
      newState: bloc.state.copyWith(contacts: updatedContacts),
    );
  }
}

class UpdateContactLastMessageUseCase
    extends UseCase<ContactsBloc, UpdateContactLastMessageEvent> {
  @override
  Future<void> execute(UpdateContactLastMessageEvent event) async {
    final updatedContacts = bloc.state.contacts.map((c) {
      if (c.id == event.contactId) {
        return c.copyWith(
          lastMessage: event.lastMessage,
          lastMessageTime: event.lastMessageTime,
          unreadCount: event.incrementUnread ? c.unreadCount + 1 : c.unreadCount,
        );
      }
      return c;
    }).toList();

    emitUpdate(
      newState: bloc.state.copyWith(contacts: updatedContacts),
    );
  }
}
