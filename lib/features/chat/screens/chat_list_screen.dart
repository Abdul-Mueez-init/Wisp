// lib/features/chat/screens/chat_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/layout_constants.dart';
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
        child: CustomScrollView(
          // Perf fix (WISP_PERFORMANCE_HANDOFF.md §7) — a single lazy
          // scroll hierarchy instead of a parent `ListView` containing
          // a nested `ListView.separated(shrinkWrap: true,
          // physics: NeverScrollableScrollPhysics())`. The nested list
          // used to force full-height layout of every row up front
          // (that's what `shrinkWrap` requires) instead of laying out
          // lazily as rows scroll into view. Same visible order (AI
          // tile → divider → conversation rows), same pull-to-refresh,
          // same navigation, same states — only the scrolling
          // container changed.
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: _AiChatTile(
                summary: aiSummary,
                onTap: () => _openAiChat(context, ref),
              ),
            ),
            SliverToBoxAdapter(
              child: Divider(
                height: 1,
                indent: 84,
                color: AppColors.outlineVariant.withValues(alpha: 0.1),
              ),
            ),
            summariesAsync.when(
              loading: () => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child:
                      Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              ),
              error: (e, _) =>
                  SliverToBoxAdapter(child: _ErrorState(message: '$e')),
              data: (_) {
                if (otherSummaries.isEmpty) {
                  return const SliverToBoxAdapter(child: _EmptyState());
                }
                // Sliver equivalent of `ListView.separated`: Flutter
                // has no stock `SliverList.separated`, so odd indices
                // render the divider and even indices render a row —
                // same visible result, still built lazily one item at
                // a time as it scrolls into view.
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      if (i.isOdd) {
                        return Divider(
                          height: 1,
                          indent: 84,
                          color:
                              AppColors.outlineVariant.withValues(alpha: 0.1),
                        );
                      }
                      return _ChatListTile(summary: otherSummaries[i ~/ 2]);
                    },
                    childCount: otherSummaries.length * 2 - 1,
                  ),
                );
              },
            ),
            // Jazz-World glass-nav pass: AppShell now runs
            // `extendBody: true` so this list's real content scrolls
            // behind the floating pill nav. Without this trailing gap,
            // the last conversation row would end up permanently
            // hidden under the (semi-transparent but still occluding)
            // pill instead of being able to scroll fully into view
            // above it.
            const SliverPadding(
              padding: EdgeInsets.only(bottom: kFloatingNavClearance),
            ),
          ],
        ),
      ),
      // BUGFIX (wisp_fixes.txt, "Ask Wisp AI button is hidden under the
      // navbar"): AppShell's outer Scaffold runs `extendBody: true` so
      // its floating glass pill paints over full-height content. This
      // screen's OWN nested Scaffold has no bottomNavigationBar of its
      // own, so Flutter's default FAB placement sits 16dp from the
      // literal bottom of the screen — the same real estate the pill
      // occupies — and the semi-transparent pill then paints over it.
      // `kFloatingNavClearance` is the exact clearance every tab's
      // scrollable content already reserves above the pill (see
      // layout_constants.dart); adding a bit more on top of that
      // (`kFabExtraLift`) is what actually gives the FAB a visible gap
      // above the pill instead of just barely clearing its top edge.
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(
          bottom: kFloatingNavClearance + kFabExtraLift,
        ),
        child: FloatingActionButton.extended(
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
      trailing: _TrailingColumn(
        timestamp: summary?.lastMessage != null
            ? formatChatTimestamp(summary!.lastMessage!.createdAt)
            : null,
        unreadCount: summary?.unreadCount ?? 0,
      ),
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

    // Perf fix (WISP_PERFORMANCE_HANDOFF.md §10) — this used to open a
    // dedicated realtime subscription per row via
    // `watchProfileProvider(userId)`, scaling linearly with the number
    // of direct chats shown. Now reads from the single app-wide
    // `presenceByIdProvider` map, selecting just this user's
    // `isOnline` value — this row only rebuilds when *this specific
    // user's* online status actually changes, not on every presence
    // tick for anyone else in the map.
    final isOnline =
        summary.conversation.isDirect && summary.otherProfile != null
            ? ref.watch(presenceByIdProvider
                .select((m) => m[summary.otherProfile!.id]?.isOnline ?? false))
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
      trailing: _TrailingColumn(
        timestamp: summary.lastMessage != null
            ? formatChatTimestamp(summary.lastMessage!.createdAt)
            : null,
        unreadCount: summary.unreadCount,
      ),
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

/// Phase 3 (wisp_fixes_handoff.md item 3, step 3) — timestamp stacked
/// above the unread badge, shared by [_AiChatTile] and [_ChatListTile]
/// so both tile types render the badge identically. Consumes the
/// existing design.md "Unread Badge: Moderate Green circle with Cream
/// label-sm text" token — no new colors/spacing invented, just the
/// same `AppColors.primaryContainer`/`AppColors.cream` pairing already
/// used for "Moderate Green" everywhere else in this codebase (sent
/// message bubbles, primary buttons).
class _TrailingColumn extends StatelessWidget {
  const _TrailingColumn({required this.timestamp, required this.unreadCount});

  final String? timestamp;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    if (timestamp == null && unreadCount <= 0) {
      return const SizedBox.shrink();
    }
    // BUGFIX ("Trailing widget consumes the entire tile width"): this
    // Column had no width cap, so on a narrow screen a longer
    // timestamp string (e.g. a full date instead of "2m") could grow
    // wide enough to starve `ListTile` of the space it needs for
    // `title`/`subtitle` — that's exactly what `ListTile` was flagging.
    // Capping this at a fixed 64px, with the timestamp itself falling
    // back to ellipsis if it's ever still too long for that budget,
    // guarantees `ListTile` always has a predictable trailing width to
    // lay out around, regardless of device width or timestamp format.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 64),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (timestamp != null)
            Text(
              timestamp!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: unreadCount > 0
                        ? AppColors.primary
                        : AppColors.onSurfaceVariant,
                  ),
            ),
          if (unreadCount > 0) ...[
            const SizedBox(height: 6),
            _UnreadBadge(count: unreadCount),
          ],
        ],
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    // wisp_fixes.txt round 2 — matched to the WhatsApp reference
    // screenshot ("make it identical with our app colours"): a solid,
    // genuinely-circular badge with a bold, punchy fill, not a soft
    // pill. Two changes from the first pass:
    //
    // 1. Fixed 22x22 box (not `minWidth`) so it's a true circle for
    //    1-2 digits like the reference, only relaxing to a pill shape
    //    once `count > 99` forces `'99+'` to not fit in a circle.
    // 2. Swapped the fill from `primaryContainer` (design.md's
    //    Buttons-section "Moderate Green", a darker/muted tone — read
    //    fine but nowhere near as punchy as the reference's vivid
    //    circle against a dark background) to `AppColors.primary`
    //    (design.md Colors section: "The Accent: Moderate Green is
    //    used surgically for... active states" — an unread count is
    //    exactly that) paired with `AppColors.onPrimary`, the token
    //    Material's own color system defines specifically as
    //    text-on-primary, for real contrast. This is a deliberate,
    //    flagged deviation from design.md's literal "Cream label-sm
    //    text" wording for this one component: `primary` (#98D2BF) is
    //    a light mint, and cream (#FBF6F0) text on it reads as barely
    //    any contrast at all — `onPrimary` (#00382C) is what actually
    //    reproduces the reference's crisp white-on-vivid-green look
    //    using only existing tokens, no new color invented.
    final isCircle = count <= 99;
    return Container(
      width: isCircle ? 22 : null,
      height: 22,
      constraints: isCircle ? null : const BoxConstraints(minWidth: 22),
      padding: isCircle
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 7),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        // `circular(11)` on a fixed 22x22 box is mathematically a
        // perfect circle (radius = half the side); on the wider
        // `minWidth` box that only kicks in for 100+ unread (a pill,
        // not a circle, at that point) it becomes a clean stadium
        // shape — one line of code covers both, no BoxShape.circle
        // ellipse-distortion risk on the non-square case.
        borderRadius: BorderRadius.all(Radius.circular(11)),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.onPrimary,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
      ),
    );
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
