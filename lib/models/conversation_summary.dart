import 'conversation.dart';
import 'message.dart';
import 'profile.dart';

/// NOT an ERD.md table — a client-side composite for the Chat List
/// screen (Batch 6b): a conversation paired with the pieces needed to
/// render one row — the other participant (direct chats only) and the
/// most recent message for the preview line.
class ConversationSummary {
  final Conversation conversation;

  /// Direct chats only — null for groups (groups use
  /// `conversation.name`/`avatarUrl` instead).
  final Profile? otherProfile;
  final Message? lastMessage;

  const ConversationSummary({
    required this.conversation,
    this.otherProfile,
    this.lastMessage,
  });

  String get displayName {
    if (conversation.isGroup) return conversation.name ?? 'Group';
    return otherProfile?.displayName ?? otherProfile?.username ?? 'Unknown';
  }
}
