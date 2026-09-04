import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../../contacts/providers/contacts_provider.dart';
import '../providers/group_provider.dart';
import '../../../widgets/error_state_view.dart';

/// Admin-only member management per PRD.md section 6: "Only the group
/// creator/admin can add/remove members and manage group settings."
/// Non-admin members see a read-only list.
class GroupMembersScreen extends ConsumerStatefulWidget {
  const GroupMembersScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<GroupMembersScreen> createState() => _GroupMembersScreenState();
}

class _GroupMembersScreenState extends ConsumerState<GroupMembersScreen> {
  String? _pendingActionUserId;

  Future<void> _removeMember(String userId) async {
    setState(() => _pendingActionUserId = userId);
    final ok = await ref
        .read(manageMembersControllerProvider.notifier)
        .removeMember(conversationId: widget.conversationId, userId: userId);
    if (!mounted) return;
    setState(() => _pendingActionUserId = null);
    if (!ok) {
      final error = ref.read(manageMembersControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error?.toString() ?? 'Could not remove member.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = ref.watch(currentSessionProvider)?.user.id;
    final membersAsync = ref.watch(groupMembersProvider(widget.conversationId));
    final myRoleAsync = ref.watch(myGroupRoleProvider(widget.conversationId));
    final isAdmin = myRoleAsync.value == 'admin';

    return Scaffold(
      backgroundColor: AppColors.backgroundBase,
      appBar: AppBar(
        title: const Text('Group members'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.person_add_alt_outlined),
              onPressed: () => showModalBottomSheet(
                context: context,
                backgroundColor: AppColors.backgroundBase,
                isScrollControlled: true,
                builder: (context) =>
                    _AddMemberSheet(conversationId: widget.conversationId),
              ),
            ),
        ],
      ),
      body: membersAsync.when(
        data: (members) {
          if (members.isEmpty) {
            return Center(
              child: Text('No members yet.',
                  style: Theme.of(context).textTheme.bodyMedium),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.pageMargin,
              vertical: 8,
            ),
            itemCount: members.length,
            separatorBuilder: (_, __) => const Divider(
              color: AppColors.outlineVariant,
              height: 1,
            ),
            itemBuilder: (context, index) {
              final member = members[index];
              final isMe = member.profile.id == myId;
              final canRemove = isAdmin && !isMe;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.surfaceContainerHigh,
                  child: Text(
                    member.profile.username.substring(0, 1).toUpperCase(),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: AppColors.primary),
                  ),
                ),
                title: Text(
                  '@${member.profile.username}${isMe ? ' (you)' : ''}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                subtitle: Text(
                  member.isAdmin ? 'Admin' : 'Member',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                trailing: !canRemove
                    ? null
                    : (_pendingActionUserId == member.profile.id
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              color: AppColors.error,
                            ),
                            onPressed: () => _removeMember(member.profile.id),
                          )),
              );
            },
          );
        },
        loading: () =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        // Phase 11 polish: friendly copy + retry instead of the raw
        // exception (e.g. this fires with a bare "permission denied"
        // string if RLS ever rejects a non-member somehow reaching
        // this screen).
        error: (e, _) => ErrorStateView(
          error: e,
          onRetry: () => ref.invalidate(
            groupMembersProvider(widget.conversationId),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet for admins to search + add new members, reusing the
/// debounced username search from Phase 2 (contacts_provider). Filters
/// out users already in the group to avoid a unique-constraint error on
/// re-insert.
class _AddMemberSheet extends ConsumerStatefulWidget {
  const _AddMemberSheet({required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends ConsumerState<_AddMemberSheet> {
  final _controller = TextEditingController();
  String? _addingUserId;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add(String userId) async {
    setState(() => _addingUserId = userId);
    final ok =
        await ref.read(manageMembersControllerProvider.notifier).addMembers(
      conversationId: widget.conversationId,
      userIds: [userId],
    );
    if (!mounted) return;
    setState(() => _addingUserId = null);
    if (!ok) {
      final error = ref.read(manageMembersControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error?.toString() ?? 'Could not add member.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final resultsAsync = ref.watch(usernameSearchControllerProvider);
    final existingMembers =
        ref.watch(groupMembersProvider(widget.conversationId)).value ?? [];
    final existingIds = existingMembers.map((m) => m.profile.id).toSet();

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.pageMargin,
        right: AppSpacing.pageMargin,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SizedBox(
        height: 420,
        child: Column(
          children: [
            Text('Add members', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(
                  color: AppColors.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              child: TextField(
                controller: _controller,
                autofocus: true,
                onChanged: (value) => ref
                    .read(usernameSearchControllerProvider.notifier)
                    .search(value),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search, color: AppColors.outline),
                  hintText: 'Search by username',
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: resultsAsync.when(
                data: (results) {
                  final filtered = results
                      .where((p) => !existingIds.contains(p.id))
                      .toList();
                  if (filtered.isEmpty) {
                    return Center(
                      child: Text(
                        _controller.text.trim().isEmpty
                            ? 'Search for people to add.'
                            : 'No matching users to add.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final profile = filtered[index];
                      final isAdding = _addingUserId == profile.id;
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 20,
                          backgroundColor: AppColors.surfaceContainerHigh,
                          child: Text(
                              profile.username.substring(0, 1).toUpperCase()),
                        ),
                        title: Text('@${profile.username}'),
                        trailing: isAdding
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : IconButton(
                                icon: const Icon(
                                  Icons.add_circle_outline,
                                  color: AppColors.primary,
                                ),
                                onPressed: () => _add(profile.id),
                              ),
                      );
                    },
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                // Phase 11 polish: no retry action here — it's a
                // debounced live-search controller, not a one-shot
                // fetch, so the natural "retry" is just editing the
                // search text again, which the user is already doing.
                error: (e, _) => ErrorStateView(error: e, compact: true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
