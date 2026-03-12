class Contact {
  final String id;
  final String name;
  final String avatarUrl;
  final bool isOnline;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;

  const Contact({
    required this.id,
    required this.name,
    this.avatarUrl = '',
    this.isOnline = false,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
  });

  Contact copyWith({
    bool? isOnline,
    String? lastMessage,
    DateTime? lastMessageTime,
    int? unreadCount,
  }) {
    return Contact(
      id: id,
      name: name,
      avatarUrl: avatarUrl,
      isOnline: isOnline ?? this.isOnline,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}
