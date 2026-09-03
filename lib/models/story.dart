import 'profile.dart';

/// Mirrors ERD.md `stories` table exactly — do not add fields here
/// that aren't in ERD.md.
class Story {
  final String id;
  final String userId;
  final String mediaUrl; // Supabase Storage path in the public `stories` bucket
  final String? caption;
  final DateTime createdAt;
  final DateTime expiresAt;

  const Story({
    required this.id,
    required this.userId,
    required this.mediaUrl,
    this.caption,
    required this.createdAt,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  factory Story.fromJson(Map<String, dynamic> json) {
    return Story(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      mediaUrl: json['media_url'] as String,
      caption: json['caption'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'media_url': mediaUrl,
        'caption': caption,
        'created_at': createdAt.toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
      };
}

/// NOT an ERD.md table — a client-side composite grouping one author's
/// active stories together, for the Status list UI (design.md's
/// "My status" / "Recent updates" / "Viewed updates" grouping, Batch
/// 6a/6b). Lives alongside Story since it's derived from the same rows,
/// not because it's a schema entity.
class StoryGroup {
  final Profile author;
  final List<Story> stories; // ordered oldest → newest
  /// Ids of [stories] the current user has already viewed, sourced
  /// from `story_views` rows the RLS policy lets them see (their own
  /// `viewer_id` rows on other people's stories, or every viewer on
  /// their own).
  final Set<String> viewedStoryIds;

  const StoryGroup({
    required this.author,
    required this.stories,
    required this.viewedStoryIds,
  });

  bool get allViewed =>
      stories.isNotEmpty && stories.every((s) => viewedStoryIds.contains(s.id));

  Story get latest => stories.last;
}

/// One viewer of a story, for the story owner's "Viewed by" list
/// (WISP_STABILITY_AND_STORY_VIEWERS_HANDOFF.md Part C). NOT an ERD.md
/// table by itself — a client-side join of `story_views` + `profiles`,
/// same "composite, not a schema entity" reasoning as [StoryGroup].
class StoryViewer {
  const StoryViewer({required this.profile, required this.viewedAt});

  final Profile profile;
  final DateTime viewedAt;

  factory StoryViewer.fromJson(Map<String, dynamic> json) => StoryViewer(
        profile: Profile.fromJson(json['profiles'] as Map<String, dynamic>),
        viewedAt: DateTime.parse(json['viewed_at'] as String),
      );
}
