/// Note color options for visual categorization.
enum NoteColor { none, red, orange, yellow, green, blue, purple }

/// A single note with support for pinning, color coding, and soft delete.
class Note {
  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isPinned;
  final NoteColor color;
  final bool isTrashed;

  const Note({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    this.isPinned = false,
    this.color = NoteColor.none,
    this.isTrashed = false,
  });

  Note copyWith({
    String? title,
    String? body,
    DateTime? updatedAt,
    bool? isPinned,
    NoteColor? color,
    bool? isTrashed,
  }) {
    return Note(
      id: id,
      title: title ?? this.title,
      body: body ?? this.body,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isPinned: isPinned ?? this.isPinned,
      color: color ?? this.color,
      isTrashed: isTrashed ?? this.isTrashed,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'isPinned': isPinned,
        'color': color.name,
        'isTrashed': isTrashed,
      };

  factory Note.fromJson(Map<String, dynamic> json) => Note(
        id: json['id'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        isPinned: json['isPinned'] as bool? ?? false,
        color: NoteColor.values.firstWhere(
          (c) => c.name == json['color'],
          orElse: () => NoteColor.none,
        ),
        isTrashed: json['isTrashed'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Note &&
          id == other.id &&
          title == other.title &&
          body == other.body &&
          isPinned == other.isPinned &&
          color == other.color &&
          isTrashed == other.isTrashed &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode =>
      Object.hash(id, title, body, isPinned, color, isTrashed, updatedAt);
}
