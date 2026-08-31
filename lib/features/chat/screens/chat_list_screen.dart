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
///
/// Phase 8 addition: a pinned "Wisp AI" tile (WhatsApp's "Meta AI" row
/// pattern) always renders first, plus an "Ask Wisp AI" FAB — both are
/// just two doors into the same reserved AI-DM conversation
/// (`ConversationRepository.findOrCreateAiConversation`). The tile is
/// rendered independently of `myConversationSummariesProvider`'s
/// loading/error states so it's never blocked behind the regular list
/// finishing its fetch (PRD.md "must feel instant").
class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  /// Shared by both the pinned tile and the FAB — resolves (creating if
  /// needed) the reserved AI conversation, then navigates into it.
  /// Mirrors `UserSearchScreen`'s `startDirectConversationWith` flow
  /// exactly (same controller shape, same error-surfacing pattern).
  Future<void> _openAiChat(BuildContext context, WidgetRef ref) async {
    final conversationId = await ref
        .read(startConversationControllerProvider.notifier)
        .openAiConversation();
    if (!context.mounted) return;

    if (conversationId != null) {
      context.push('/chat/$conversationId?ai=true');
    } else {
      final error = ref.read(startConversationControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error?.toString() ?? 'Could not open Wisp AI.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summariesAsync = ref.watch(myConversationSummariesProvider);
    final openingAiChat =
        ref.watch(startConversationControllerProvider).isLoading;

    // The AI thread only exists as a real `conversations` row once
    // opened at least once (`findOrCreateAiConversation` is lazy) — so
    // its preview/timestamp are optional extras layered onto an always-
    // present pinned tile, not a precondition for showing it at all.
    final allSummaries = summariesAsync.value ?? const <ConversationSummary>[];
    ConversationSummary? aiSummary;
    final otherSummaries = <ConversationSummary>[];
    for (final s in allSummaries) {
      if (s.isAiConversation) {
        aiSummary = s;
      } else {
        otherSummaries.add(s);
      }
    }

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
        child: ListView(
          children: [
            _AiChatTile(
              summary: aiSummary,
              onTap: () => _openAiChat(context, ref),
            ),
            Divider(
              height: 1,
              indent: 84,
              color: AppColors.outlineVariant.withValues(alpha: 0.1),
            ),
            summariesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (e, _) => _ErrorState(message: '$e'),
              data: (_) {
                if (otherSummaries.isEmpty) return const _EmptyState();
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: otherSummaries.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    indent: 84,
                    color: AppColors.outlineVariant.withValues(alpha: 0.1),
                  ),
                  itemBuilder: (context, i) =>
                      _ChatListTile(summary: otherSummaries[i]),
                );
              },
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: openingAiChat ? null : () => _openAiChat(context, ref),
        backgroundColor: AppColors.primaryContainer,
        foregroundColor: AppColors.primary,
        icon: openingAiChat
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.primary),
              )
            : const Icon(Icons.auto_awesome),
        label: const Text('Ask Wisp AI'),
      ),
    );
  }
}

/// The pinned "Wisp AI" row — same avatar/icon treatment as
/// `ChatDetailScreen`'s AppBar for the AI conversation
/// (`AppColors.primaryContainer` + `Icons.auto_awesome`), so the two
/// entry points read as clearly the same destination. Always rendered,
/// whether or not the AI conversation has been opened/created yet.
class _AiChatTile extends StatelessWidget {
  const _AiChatTile({required this.summary, required this.onTap});

  /// Null until the user has opened the AI chat at least once — the
  /// tile still renders with a placeholder subtitle in that case.
  final ConversationSummary? summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.pageMargin, vertical: 4),
      onTap: onTap,
      leading: const CircleAvatar(
        radius: 28,
        backgroundColor: AppColors.primaryContainer,
        child: Icon(Icons.auto_awesome, color: AppColors.primary),
      ),
      title: Text(
        'Wisp AI',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      subtitle: Text(
        summary?.lastMessage != null
            ? _previewText(summary!.lastMessage!)
            : 'Ask me anything ✨',
        style: Theme.of(context).textTheme.bodyMedium,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: summary?.lastMessage != null
          ? Text(
              formatChatTimestamp(summary!.lastMessage!.createdAt),
              style: Theme.of(context).textTheme.labelSmall,
            )
          : null,
    );
  }

  String _previewText(Message message) {
    switch (message.type) {
      case 'text':
        return message.content ?? '';
      case 'voice':
        return '🎤 Voice message';
      default:
        return message.content ?? '';
    }
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
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.pageMargin * 2),
      child: Text(
        'No chats yet. Tap the search icon above to find someone to message.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.pageMargin),
      child: Text(
        message,
        style: const TextStyle(color: AppColors.error),
        textAlign: TextAlign.center,
      ),
    );
  }
}
