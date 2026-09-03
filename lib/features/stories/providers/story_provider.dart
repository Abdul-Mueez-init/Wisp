// lib/features/stories/providers/story_provider.dart
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/supabase_config.dart';
import '../../../core/errors/failure.dart';
import '../../../models/story.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/story_repository.dart';

final storyRepositoryProvider = Provider<StoryRepository>((ref) {
  return StoryRepository(SupabaseConfig.client);
});

/// All active (non-expired) story groups visible to the signed-in user.
/// FutureProvider, not StreamProvider — the query is a multi-table join
/// (`profiles`, `story_views`), which Supabase's `.stream()` doesn't
/// support (same reasoning as `conversationByIdProvider`). Invalidated
/// manually after posting/viewing rather than polled.
final activeStoryGroupsProvider = FutureProvider<List<StoryGroup>>((ref) async {
  final myId = ref.watch(currentSessionProvider)?.user.id;
  if (myId == null) return const [];
  return ref
      .read(storyRepositoryProvider)
      .fetchActiveStoryGroups(currentUserId: myId);
});

/// Public bucket → plain URL resolution, no async Storage round trip
/// needed. Kept as a provider for call-shape consistency with
/// `mediaSignedUrlProvider` in bubble/preview widgets.
final storyMediaUrlProvider = Provider.family<String, String>((ref, path) {
  return ref.read(storyRepositoryProvider).resolveMediaUrl(path);
});

/// One-off action: capture/pick media + caption → upload + insert.
/// Mirrors `SendMediaMessageController`'s AsyncNotifier shape.
class PostStoryController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<bool> post({
    required Uint8List bytes,
    required String fileExt,
    String? caption,
    String? contentType,
  }) async {
    final myId = ref.read(currentSessionProvider)?.user.id;
    if (myId == null) {
      state = AsyncError(
        const AuthFailure('No authenticated session found.'),
        StackTrace.current,
      );
      return false;
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(storyRepositoryProvider).createStory(
              userId: myId,
              bytes: bytes,
              fileExt: fileExt,
              caption: caption,
              contentType: contentType,
            ));
    final success = !state.hasError;
    if (success) ref.invalidate(activeStoryGroupsProvider);
    return success;
  }
}

final postStoryControllerProvider =
    AsyncNotifierProvider<PostStoryController, void>(PostStoryController.new);

/// One-shot fetch per story — a viewer list doesn't need to be
/// realtime-streamed (matches WhatsApp: opening the viewer list shows a
/// snapshot, it doesn't live-update while you're looking at it), so a
/// plain FutureProvider.family is the right shape per architecture.md's
/// "one-off actions/reads → Notifier/AsyncNotifier or FutureProvider,
/// only continuously-changing data → StreamProvider" split. Part C of
/// the stability/story-viewers handoff doc.
final storyViewersProvider =
    FutureProvider.family<List<StoryViewer>, String>((ref, storyId) {
  return ref.read(storyRepositoryProvider).fetchViewers(storyId);
});
