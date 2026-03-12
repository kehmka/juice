class Message {
  final String id;
  final String senderId;
  final String receiverId;
  final String text;
  final DateTime timestamp;
  final bool isRead;

  const Message({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.text,
    required this.timestamp,
    this.isRead = false,
  });

  Message copyWith({bool? isRead}) {
    return Message(
      id: id,
      senderId: senderId,
      receiverId: receiverId,
      text: text,
      timestamp: timestamp,
      isRead: isRead ?? this.isRead,
    );
  }

  bool get isSentByMe => senderId == 'me';

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderId': senderId,
        'receiverId': receiverId,
        'text': text,
        'timestamp': timestamp.toIso8601String(),
        'isRead': isRead,
      };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'] as String,
        senderId: json['senderId'] as String,
        receiverId: json['receiverId'] as String,
        text: json['text'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        isRead: json['isRead'] as bool? ?? false,
      );
}
