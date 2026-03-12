import 'package:flutter/material.dart';
import 'package:juice/juice.dart';
import '../blocs/contacts_bloc.dart';
import '../blocs/chat_bloc.dart';
import '../blocs/chat_events.dart';
import '../models/contact.dart';
import 'chat_screen.dart';

class ConversationsScreen extends StatelessJuiceWidget<ContactsBloc> {
  ConversationsScreen({super.key})
      : super(groups: const {'contacts:list', 'contacts:status'});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    if (status is WaitingStatus) {
      return Scaffold(
        appBar: AppBar(title: const Text('Messages')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final contacts = bloc.state.contacts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        elevation: 1,
      ),
      body: ListView.separated(
        itemCount: contacts.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, index) {
          final contact = contacts[index];
          return _ContactTile(
            contact: contact,
            onTap: () {
              final chatBloc = BlocScope.get<ChatBloc>();
              chatBloc.send(LoadMessagesEvent(contactId: contact.id));
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChatScreen(contact: contact),
                ),
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget close(BuildContext context) => const SizedBox.shrink();
}

class _ContactTile extends StatelessWidget {
  final Contact contact;
  final VoidCallback onTap;

  const _ContactTile({required this.contact, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.blueGrey[100],
            child: Text(
              contact.name[0],
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: contact.isOnline ? Colors.green : Colors.grey,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
      title: Text(
        contact.name,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        contact.lastMessage ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: contact.unreadCount > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${contact.unreadCount}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            )
          : null,
      onTap: onTap,
    );
  }
}
