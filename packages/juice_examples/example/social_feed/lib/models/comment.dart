class Comment {
  final int id;
  final String body;
  final int postId;
  final int likes;
  final String userName;

  const Comment({
    required this.id,
    required this.body,
    required this.postId,
    this.likes = 0,
    required this.userName,
  });

  factory Comment.fromJson(Map<String, dynamic> json) => Comment(
        id: json['id'] as int,
        body: json['body'] as String,
        postId: json['postId'] as int,
        likes: json['likes'] as int? ?? 0,
        userName: json['user']?['username'] as String? ?? 'anonymous',
      );
}
