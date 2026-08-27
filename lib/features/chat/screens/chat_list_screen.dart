// lib/features/chat/screens/chat_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format_utils.dart';
import '../../../models/conversation_summary.dart';
import '../../../models/message.dart';
import '../../profile/providers/profile_provider.dart';
import '../providers/conversation_provider.dart';
import '../providers/presence_provider.dart';

/// Chats tab (plan.md Phase 6, batch 6b) — the chat list flagged as
/// missing since Phase 2/3 (context.md open issues). design.md "Lists"
/// component: avatar left, two lines of text (name / preview), 1px
/// Laurel Green divider at 10% opacity between rows.
class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summariesAsync = ref.watch(myConversationSummariesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wisp'),
        actions: [
          IconButton(
            tooltip: 'Find people',
            icon: const Icon(Icons.person_search_outlined),
            onPressed: () => context.push('/search'),
          ),
          IconButton(
            tooltip: 'New group',
            icon: const Icon(Icons.group_add_outlined),
            onPressed: () => context.push('/group/new'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(myConversationSummariesProvider.future),
        child: summariesAsync.when(
          loading: () =>
              const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          error: (e, _) => _ErrorState(message: '$e'),
          data: (summaries) {
            if (summaries.isEmpty) return const _EmptyState();
            return ListView.separated(
              itemCount: summaries.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                indent: 84,
                color: AppColors.outlineVariant.withValues(alpha: 0.1),
              ),
              itemBuilder: (context, i) => _ChatListTile(summary: summaries[i]),
            );
          },
        ),
      ),
    );
  }
}

class _ChatListTile extends ConsumerWidget {
  const _ChatListTile({required this.summary});
  final ConversationSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Group avatar upload has no bucket/flow yet anywhere in the repo
    // (architecture.md's Storage Buckets only covers `avatars` and
    // `chat-media`) — `conversation.avatar_url` is currently always
    // null in practice, so groups render initials only. Flagging
    // rather than silently building a resolver for a path shape that
    // doesn't exist yet.
    final rawAvatarPath =
        summary.conversation.isDirect ? summary.otherProfile?.avatarUrl : null;
    final avatarUrl = rawAvatarPath != null
        ? ref.read(profileRepositoryProvider).resolveAvatarUrl(rawAvatarPath)
        : null;

    final isOnline = summary.conversation.isDirect &&
            summary.otherProfile != null
        ? ref
            .watch(watchProfileProvider(summary.otherProfile!.id))
            .maybeWhen(data: (p) => p?.isOnline ?? false, orElse: () => false)
        : false;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.pageMargin, vertical: 4),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.surfaceContainerHigh,
            backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
            child: avatarUrl == null
                ? Text(summary.displayName.isNotEmpty
                    ? summary.displayName[0].toUpperCase()
                    : '?')
                : null,
          ),
          if (isOnline)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary,
                  border: Border.all(color: AppColors.backgroundBase, width: 2),
                ),
              ),
            ),
        ],
      ),
      title: Text(
        summary.displayName,
        style: Theme.of(context).textTheme.titleMedium,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        _previewText(summary.lastMessage),
        style: Theme.of(context).textTheme.bodyMedium,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: summary.lastMessage != null
          ? Text(
              formatChatTimestamp(summary.lastMessage!.createdAt),
              style: Theme.of(context).textTheme.labelSmall,
            )
          : null,
      onTap: () => context.push(
        '/chat/${summary.conversation.id}',
        extra: summary.conversation.isDirect
            ? summary.otherProfile
            : summary.conversation,
      ),
    );
  }

  String _previewText(Message? message) {
    if (message == null) return 'Say hi 👋';
    switch (message.type) {
      case 'text':
        return message.content ?? '';
      case 'image':
        return '📷 Photo';
      case 'video':
        return '🎥 Video';
      case 'voice':
        return '🎤 Voice message';
      case 'document':
        return '📄 Document';
      case 'contact':
        return '👤 Contact';
      case 'location_current':
        return '📍 Location';
      case 'location_live':
        return '📍 Live location';
      default:
        return message.content ?? '';
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
        child: Text(
          'No chats yet. Tap the search icon above to find someone to message.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.pageMargin),
        child: Text(
          message,
          style: const TextStyle(color: AppColors.error),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
