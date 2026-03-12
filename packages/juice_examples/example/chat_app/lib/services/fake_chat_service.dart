import 'dart:async';
import 'dart:math';
import '../models/message.dart';
import '../models/contact.dart';

/// Simulates a real-time chat backend using timers.
class FakeChatService {
  final _messageController = StreamController<Message>.broadcast();
  final _typingController = StreamController<String>.broadcast();
  final _statusController = StreamController<(String, bool)>.broadcast();
  final _random = Random();
  Timer? _autoReplyTimer;
  Timer? _statusTimer;

  Stream<Message> get incomingMessages => _messageController.stream;
  Stream<String> get typingIndicators => _typingController.stream;
  Stream<(String, bool)> get onlineStatusChanges => _statusController.stream;

  static const _autoReplies = [
    'Interesting! Tell me more.',
    'That sounds great!',
    'I was just thinking the same thing.',
    'Ha, nice one!',
    'Got it, thanks!',
    'Let me think about that...',
    'Sure, no problem!',
    'Wow, really?',
    'I agree completely.',
    'That makes sense.',
  ];

  List<Contact> getContacts() {
    return const [
      Contact(
        id: 'alice',
        name: 'Alice Johnson',
        isOnline: true,
        lastMessage: 'Hey, how are you?',
      ),
      Contact(
        id: 'bob',
        name: 'Bob Smith',
        isOnline: false,
        lastMessage: 'See you tomorrow!',
      ),
      Contact(
        id: 'carol',
        name: 'Carol Williams',
        isOnline: true,
        lastMessage: 'The project looks great',
      ),
      Contact(
        id: 'dave',
        name: 'Dave Brown',
        isOnline: false,
        lastMessage: 'Thanks for the help',
      ),
      Contact(
        id: 'eve',
        name: 'Eve Davis',
        isOnline: true,
        lastMessage: 'Let me check and get back to you',
      ),
    ];
  }

  void sendMessage(Message message) {
    _scheduleAutoReply(message.receiverId);
  }

  void _scheduleAutoReply(String contactId) {
    _autoReplyTimer?.cancel();

    // Show typing indicator after a short delay
    Timer(Duration(milliseconds: 500 + _random.nextInt(1000)), () {
      _typingController.add(contactId);
    });

    // Send auto-reply after 2-4 seconds
    _autoReplyTimer = Timer(
      Duration(milliseconds: 2000 + _random.nextInt(2000)),
      () {
        _typingController.add(''); // Clear typing
        _messageController.add(Message(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          senderId: contactId,
          receiverId: 'me',
          text: _autoReplies[_random.nextInt(_autoReplies.length)],
          timestamp: DateTime.now(),
        ));
      },
    );
  }

  void startStatusSimulation() {
    final contacts = ['alice', 'bob', 'carol', 'dave', 'eve'];
    _statusTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      final contactId = contacts[_random.nextInt(contacts.length)];
      final isOnline = _random.nextBool();
      _statusController.add((contactId, isOnline));
    });
  }

  void dispose() {
    _autoReplyTimer?.cancel();
    _statusTimer?.cancel();
    _messageController.close();
    _typingController.close();
    _statusController.close();
  }
}
