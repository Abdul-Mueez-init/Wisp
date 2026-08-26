import 'profile.dart';

/// Mirrors ERD.md `conversation_members` table, joined with the
/// member's `profiles` row for display purposes. Do not add fields
/// here that aren't in ERD.md/profiles.dart.
class ConversationMember {
  final String id;
  final String conversationId;
  final String role; // 'admin' or 'member'
  final DateTime joinedAt;
  final Profile profile;

  const ConversationMember({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.joinedAt,
    required this.profile,
  });

  bool get isAdmin => role == 'admin';

  factory ConversationMember.fromJoinedJson(Map<String, dynamic> json) {
    return ConversationMember(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      role: json['role'] as String,
      joinedAt: DateTime.parse(json['joined_at'] as String),
      profile: Profile.fromJson(json['profiles'] as Map<String, dynamic>),
    );
  }
}
