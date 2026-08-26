import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/supabase_config.dart';
import '../../../core/errors/failure.dart';
import '../../../models/conversation_member.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/group_repository.dart';

final groupRepositoryProvider = Provider<GroupRepository>((ref) {
  return GroupRepository(SupabaseConfig.client);
});

/// One-off action: create a group per PRD.md section 6. Returns the new
/// conversation id on success so the UI can navigate straight into it.
class CreateGroupController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<String?> createGroup({
    required String name,
    required List<String> memberIds,
  }) async {
    final myId = ref.read(currentSessionProvider)?.user.id;
    if (myId == null) {
      state = AsyncError(
        const AuthFailure('No authenticated session found.'),
        StackTrace.current,
      );
      return null;
    }

    state = const AsyncLoading();
    String? conversationId;
    state = await AsyncValue.guard(() async {
      final conversation = await ref.read(groupRepositoryProvider).createGroup(
            creatorId: myId,
            name: name,
            memberIds: memberIds,
          );
      conversationId = conversation.id;
    });
    return conversationId;
  }
}

final createGroupControllerProvider =
    AsyncNotifierProvider<CreateGroupController, void>(
  CreateGroupController.new,
);

/// Full membership list for the group members screen. Re-fetched via
/// `ref.invalidate` after add/remove — see ManageMembersController.
final groupMembersProvider =
    FutureProvider.family<List<ConversationMember>, String>(
  (ref, conversationId) {
    return ref.read(groupRepositoryProvider).fetchMembers(conversationId);
  },
);

/// The current user's role in [conversationId] — null if not a member.
/// Gates the admin-only add/remove UI per PRD.md section 6.
final myGroupRoleProvider =
    FutureProvider.family<String?, String>((ref, conversationId) async {
  final myId = ref.watch(currentSessionProvider)?.user.id;
  if (myId == null) return null;
  return ref
      .read(groupRepositoryProvider)
      .myRole(conversationId: conversationId, userId: myId);
});

/// One-off admin actions: add/remove members. Invalidates
/// [groupMembersProvider] on success so the members screen refreshes.
class ManageMembersController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<bool> addMembers({
    required String conversationId,
    required List<String> userIds,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(groupRepositoryProvider).addMembers(
            conversationId: conversationId,
            userIds: userIds,
          ),
    );
    if (!state.hasError) {
      ref.invalidate(groupMembersProvider(conversationId));
    }
    return !state.hasError;
  }

  Future<bool> removeMember({
    required String conversationId,
    required String userId,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(groupRepositoryProvider).removeMember(
            conversationId: conversationId,
            userId: userId,
          ),
    );
    if (!state.hasError) {
      ref.invalidate(groupMembersProvider(conversationId));
    }
    return !state.hasError;
  }
}

final manageMembersControllerProvider =
    AsyncNotifierProvider<ManageMembersController, void>(
  ManageMembersController.new,
);
