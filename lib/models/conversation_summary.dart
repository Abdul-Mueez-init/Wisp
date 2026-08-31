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

  /// Phase 8 — derived, not stored (per `ConversationRepository
  /// .findOrCreateAiConversation`'s doc comment: the AI-DM thread is an
  /// ordinary `type: 'direct'` conversation whose *only*
  /// `conversation_members` row is the user themself). A real
  /// human-to-human direct conversation always has an `otherProfile`
  /// resolved by `getOtherDirectMember`; the reserved AI thread never
  /// does, since there's no second member to find. That gap is exactly
  /// what identifies it here — no new column, no schema change.
  bool get isAiConversation => conversation.isDirect && otherProfile == null;

  String get displayName {
    if (isAiConversation) return 'Wisp AI';
    if (conversation.isGroup) return conversation.name ?? 'Group';
    return otherProfile?.displayName ?? otherProfile?.username ?? 'Unknown';
  }
}
