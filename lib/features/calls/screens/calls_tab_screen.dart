// lib/features/calls/screens/calls_tab_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format_utils.dart';
import '../../../models/call.dart';
import '../../../models/profile.dart';
import '../../auth/providers/auth_provider.dart';
import '../../chat/providers/message_provider.dart';
import '../../profile/providers/profile_provider.dart';
import '../providers/call_controller.dart';
import '../providers/call_provider.dart';

/// Calls tab (Batch 10c) — replaces AppShell's `_CallsStubScreen`.
/// Per the Phase 10 handoff doc §3.5 (confirmed): call history is
/// surfaced here only, not as an in-chat message bubble — there is no
/// `messages.type == 'call'` and never will be under this decision.
///
/// `calls` has no `callee_id` column (ERD.md), so "who was this call
/// with" is always resolved the same way the chat list already does:
/// the other member of the call's (always-direct, PRD.md §11) 1-on-1
/// conversation — via [otherDirectMemberProvider] — regardless of
/// which side placed the call.
class CallsTabScreen extends ConsumerWidget {
  const CallsTabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callsAsync = ref.watch(myVisibleCallsStreamProvider);
    final myId = ref.watch(currentSessionProvider)?.user.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Calls')),
      body: callsAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.pageMargin),
            child: Text(
              'Could not load call history.\n$e',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
        data: (calls) {
          if (myId == null) return const SizedBox.shrink();
          final sorted = [...calls]..sort((a, b) {
              final aTime =
                  a.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bTime =
                  b.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              return bTime.compareTo(aTime);
            });

          if (sorted.isEmpty) return const _EmptyState();

          return ListView.separated(
            itemCount: sorted.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              indent: 84,
              color: AppColors.outlineVariant.withValues(alpha: 0.1),
            ),
            itemBuilder: (context, i) =>
                _CallHistoryTile(call: sorted[i], myId: myId),
          );
        },
      ),
    );
  }
}

class _CallHistoryTile extends ConsumerWidget {
  const _CallHistoryTile({required this.call, required this.myId});

  final Call call;
  final String myId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final otherProfileAsync =
        ref.watch(otherDirectMemberProvider(call.conversationId));
    final otherProfile = otherProfileAsync.value;
    final displayName = otherProfile?.displayName?.isNotEmpty == true
        ? otherProfile!.displayName!
        : (otherProfile != null ? '@${otherProfile.username}' : 'Wisp user');

    final isOutgoing = call.callerId == myId;
    final isMissedOrDeclined = call.isMissedOrDeclined;
    // "Missed" from my point of view only applies when I was the
    // callee — an outgoing call I cancelled/that wasn't picked up
    // reads as "No answer" rather than "Missed call", matching
    // WhatsApp's own framing of the two sides of the same event.
    final subtitleColor =
        (!isOutgoing && isMissedOrDeclined) ? AppColors.error : null;

    final rawAvatarPath = otherProfile?.avatarUrl;
    final avatarUrl = rawAvatarPath != null
        ? ref.read(profileRepositoryProvider).resolveAvatarUrl(rawAvatarPath)
        : null;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.pageMargin, vertical: 4),
      leading: CircleAvatar(
        radius: 28,
        backgroundColor: AppColors.surfaceContainerHigh,
        backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
        child: avatarUrl == null
            ? Text(displayName.isNotEmpty ? displayName[0].toUpperCase() : '?')
            : null,
      ),
      title: Text(
        displayName,
        style: Theme.of(context).textTheme.titleMedium,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          Icon(
            isOutgoing ? Icons.call_made : Icons.call_received,
            size: 14,
            color: subtitleColor ?? AppColors.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            _subtitleText(isOutgoing),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: subtitleColor,
                ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (call.startedAt != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                formatChatTimestamp(call.startedAt!),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          IconButton(
            icon: Icon(
                call.isVideo ? Icons.videocam_outlined : Icons.call_outlined),
            color: AppColors.primary,
            onPressed: otherProfile == null
                ? null
                : () => _redial(context, ref, otherProfile),
          ),
        ],
      ),
    );
  }

  String _subtitleText(bool isOutgoing) {
    final kind = call.isVideo ? 'Video' : 'Audio';
    if (call.status == 'missed')
      return isOutgoing ? '$kind • No answer' : '$kind • Missed';
    if (call.status == 'declined')
      return isOutgoing ? '$kind • Declined' : '$kind • Declined';
    return isOutgoing ? '$kind • Outgoing' : '$kind • Incoming';
  }

  Future<void> _redial(
    BuildContext context,
    WidgetRef ref,
    Profile otherProfile,
  ) async {
    final controller = ref.read(callControllerProvider.notifier);
    final ok = await controller.startCall(
      conversationId: call.conversationId,
      calleeId: otherProfile.id,
      isVideo: call.isVideo,
    );
    if (ok && context.mounted) {
      context.push('/call');
    } else if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not start the call.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.pageMargin),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.call_outlined, size: 48, color: AppColors.outline),
            const SizedBox(height: AppSpacing.stackDefault),
            Text(
              'No calls yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.stackCompact),
            Text(
              'Calls you make or receive will show up here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
