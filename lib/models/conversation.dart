/// Mirrors ERD.md `conversations` table exactly — do not add fields
/// here that aren't in ERD.md.
class Conversation {
  final String id;
  final String type; // 'direct' or 'group'
  final String? name;
  final String? avatarUrl;
  // Nullable per seed.sql (`created_by uuid references profiles(id)` has
  // no not-null constraint), even though ERD.md's prose doesn't call
  // out nullability explicitly.
  final String? createdBy;
  final DateTime createdAt;

  const Conversation({
    required this.id,
    required this.type,
    this.name,
    this.avatarUrl,
    this.createdBy,
    required this.createdAt,
  });

  bool get isDirect => type == 'direct';
  bool get isGroup => type == 'group';

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] as String,
      type: json['type'] as String,
      name: json['name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      createdBy: json['created_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'name': name,
        'avatar_url': avatarUrl,
        'created_by': createdBy,
        'created_at': createdAt.toIso8601String(),
      };
}
