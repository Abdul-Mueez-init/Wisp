// lib/features/stories/data/story_repository.dart
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/failure.dart';
import '../../../models/profile.dart';
import '../../../models/story.dart';

/// All `stories`/`story_views` table + `stories` Storage bucket access
/// goes through here — same shape as MediaRepository/ProfileRepository
/// (rules.md Rule 8 pattern, extended to the stories domain).
///
/// Bucket: `stories` — PUBLIC, mirrors `avatars`. See handoff doc: since
/// `stories_select_all` RLS is already `using (true)`, a private +
/// signed-URL bucket would add chat-media-style complexity for zero
/// actual privacy benefit.
class StoryRepository {
  StoryRepository(this._client);
  final SupabaseClient _client;

  static const bucket = 'stories';

  /// Same client-side-guardrail reasoning as MediaRepository — not a
  /// server-enforced cap, just a sane limit on the free-tier quota.
  static const maxImageBytes = 8 * 1024 * 1024; // 8MB
  static const maxVideoBytes = 50 * 1024 * 1024; // 50MB

  /// Path convention: `{user_id}/{story_id}/{filename}` — same shape as
  /// `chat-media`, minus the signed-URL step since this bucket's public.
  Future<String> _uploadMedia({
    required String userId,
    required String storyId,
    required String fileName,
    required Uint8List bytes,
    String? contentType,
  }) async {
    final safeName = _sanitizeFileName(fileName);
    final path = '$userId/$storyId/$safeName';
    try {
      await _client.storage.from(bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(upsert: true, contentType: contentType),
          );
      return path;
    } on StorageException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  /// Public bucket — plain `getPublicUrl`, no signed-URL round trip
  /// (unlike `MediaRepository.resolveSignedUrl`).
  String resolveMediaUrl(String mediaPath) {
    return _client.storage.from(bucket).getPublicUrl(mediaPath);
  }

  /// Uploads the media and inserts the `stories` row in one call —
  /// mirrors `SendMediaMessageController`'s upload-then-insert shape.
  Future<Story> createStory({
    required String userId,
    required Uint8List bytes,
    required String fileExt,
    String? caption,
    String? contentType,
  }) async {
    final storyId = const Uuid().v4();
    try {
      final path = await _uploadMedia(
        userId: userId,
        storyId: storyId,
        fileName: 'story.$fileExt',
        bytes: bytes,
        contentType: contentType,
      );
      final row = await _client
          .from('stories')
          .insert({
            'id': storyId,
            'user_id': userId,
            'media_url': path,
            'caption': (caption == null || caption.trim().isEmpty)
                ? null
                : caption.trim(),
          })
          .select()
          .single();
      return Story.fromJson(row);
    } on PostgrestException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  /// Fetches every non-expired story visible to [currentUserId]
  /// (`stories_select_all` = every authenticated user), grouped by
  /// author, each with the set of story ids [currentUserId] has already
  /// viewed. Client-side `expires_at` filter — no cron/Edge Function,
  /// same zero-cost reasoning as 5e's live-location expiry (and 6c's
  /// planned auto-expiry).
  Future<List<StoryGroup>> fetchActiveStoryGroups({
    required String currentUserId,
  }) async {
    try {
      final rows = await _client
          .from('stories')
          .select('*, profiles!inner(*), story_views(viewer_id)')
          .order('created_at', ascending: true);

      final now = DateTime.now();
      final byUser = <String, List<Map<String, dynamic>>>{};
      final profilesByUser = <String, Profile>{};

      for (final raw in rows as List) {
        final row = raw as Map<String, dynamic>;
        final expiresAt = DateTime.parse(row['expires_at'] as String);
        if (!expiresAt.isAfter(now)) continue; // expired — skip client-side

        final userId = row['user_id'] as String;
        byUser.putIfAbsent(userId, () => []).add(row);
        profilesByUser.putIfAbsent(
          userId,
          () => Profile.fromJson(row['profiles'] as Map<String, dynamic>),
        );
      }

      return byUser.entries.map((entry) {
        final stories = entry.value.map((r) => Story.fromJson(r)).toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

        final viewedIds = <String>{};
        for (final row in entry.value) {
          final views = row['story_views'] as List? ?? const [];
          final iViewedThis = views.any(
            (v) => (v as Map<String, dynamic>)['viewer_id'] == currentUserId,
          );
          if (iViewedThis) viewedIds.add(row['id'] as String);
        }

        return StoryGroup(
          author: profilesByUser[entry.key]!,
          stories: stories,
          viewedStoryIds: viewedIds,
        );
      }).toList();
    } on PostgrestException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  /// Records that [viewerId] has seen [storyId]. `unique(story_id,
  /// viewer_id)` in seed.sql makes this idempotent via upsert. Wired up
  /// in 6c's story viewer screen — defined here now since it's a
  /// trivial one-line write on a table this repository already owns.
  Future<void> recordView({
    required String storyId,
    required String viewerId,
  }) async {
    try {
      await _client.from('story_views').upsert(
        {'story_id': storyId, 'viewer_id': viewerId},
        onConflict: 'story_id,viewer_id',
      );
    } on PostgrestException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  String _sanitizeFileName(String name) {
    final base = name.split('/').last.split('\\').last;
    final cleaned = base.replaceAll(RegExp(r'[^\w.\-]'), '_');
    return cleaned.isEmpty ? 'file' : cleaned;
  }
}
