import 'package:flutter/material.dart';
import 'package:juice/juice.dart';
import '../blocs/chat_bloc.dart';
import '../blocs/contacts_bloc.dart';
import '../blocs/chat_events.dart';
import '../blocs/contacts_events.dart';
import '../models/contact.dart';
import '../models/message.dart';
import 'contact_detail_screen.dart';

/// Demonstrates JuiceBuilder2 — observing ChatBloc and ContactsBloc together.
class ChatScreen extends StatefulWidget {
  final Contact contact;

  const ChatScreen({super.key, required this.contact});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final chatBloc = BlocScope.get<ChatBloc>();
    chatBloc.send(SendMessageEvent(
      text: text,
      receiverId: widget.contact.id,
    ));

    final contactsBloc = BlocScope.get<ContactsBloc>();
    contactsBloc.send(UpdateContactLastMessageEvent(
      contactId: widget.contact.id,
      lastMessage: text,
      lastMessageTime: DateTime.now(),
    ));

    _textController.clear();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: JuiceBuilder<ContactsBloc>(
          groups: const {'contacts:status'},
          builder: (context, contactsBloc, status) {
            final contact = contactsBloc.state.contacts
                .where((c) => c.id == widget.contact.id)
                .firstOrNull;
            return GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      ContactDetailScreen(contact: contact ?? widget.contact),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.contact.name),
                  const SizedBox(width: 8),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (contact?.isOnline ?? false)
                          ? Colors.green
                          : Colors.grey,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: JuiceBuilder2<ChatBloc, ContactsBloc>(
              groups: const {'chat:messages', 'chat:typing'},
              builder: (context, chatBloc, contactsBloc, status) {
                final messages = chatBloc.state.activeMessages;
                _scrollToBottom();

                return Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          return _MessageBubble(message: messages[index]);
                        },
                      ),
                    ),
                    if (chatBloc.state.peerIsTyping)
                      Padding(
                        padding: const EdgeInsets.only(left: 16, bottom: 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${widget.contact.name} is typing...',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontStyle: FontStyle.italic,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _sendMessage,
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Message message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isMine = message.isSentByMe;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints:
              BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isMine
                ? colorScheme.primary
                : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: isMine
                  ? const Radius.circular(16)
                  : const Radius.circular(4),
              bottomRight: isMine
                  ? const Radius.circular(4)
                  : const Radius.circular(16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                message.text,
                style: TextStyle(
                  color: isMine ? colorScheme.onPrimary : colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _formatTime(message.timestamp),
                style: TextStyle(
                  fontSize: 11,
                  color: isMine
                      ? colorScheme.onPrimary.withValues(alpha: 0.7)
                      : colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
