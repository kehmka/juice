class Post {
  final int id;
  final String title;
  final String body;
  final int userId;
  final List<String> tags;
  final int likes;
  final int dislikes;
  final int views;

  const Post({
    required this.id,
    required this.title,
    required this.body,
    required this.userId,
    this.tags = const [],
    this.likes = 0,
    this.dislikes = 0,
    this.views = 0,
  });

  Post copyWith({int? likes}) {
    return Post(
      id: id,
      title: title,
      body: body,
      userId: userId,
      tags: tags,
      likes: likes ?? this.likes,
      dislikes: dislikes,
      views: views,
    );
  }

  factory Post.fromJson(Map<String, dynamic> json) => Post(
        id: json['id'] as int,
        title: json['title'] as String,
        body: json['body'] as String,
        userId: json['userId'] as int,
        tags: (json['tags'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        likes: json['reactions']?['likes'] as int? ?? 0,
        dislikes: json['reactions']?['dislikes'] as int? ?? 0,
        views: json['views'] as int? ?? 0,
      );
}
