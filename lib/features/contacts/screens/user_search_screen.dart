import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/profile.dart';
import '../../chat/providers/conversation_provider.dart';
import '../providers/contacts_provider.dart';

/// Built off the Stitch `user_search_contact_discovery` export: search
/// field with clear button, "Matching users" result list, empty state.
class UserSearchScreen extends ConsumerStatefulWidget {
  const UserSearchScreen({super.key});

  @override
  ConsumerState<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends ConsumerState<UserSearchScreen> {
  final _controller = TextEditingController();
  String? _startingConversationForUserId;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _startChat(Profile profile) async {
    setState(() => _startingConversationForUserId = profile.id);
    final conversationId = await ref
        .read(startConversationControllerProvider.notifier)
        .startDirectConversationWith(profile.id);
    if (!mounted) return;
    setState(() => _startingConversationForUserId = null);

    if (conversationId != null) {
      context.push('/chat/$conversationId', extra: profile);
    } else {
      final error = ref.read(startConversationControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error?.toString() ?? 'Could not start conversation.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final resultsAsync = ref.watch(usernameSearchControllerProvider);
    final hasQuery = _controller.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.backgroundBase,
      appBar: AppBar(
        title: const Text('Find people'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.pageMargin,
              vertical: 12,
            ),
            child: Container(
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
                style: Theme.of(context).textTheme.bodyLarge,
                onChanged: (value) {
                  setState(() {}); // refresh clear button + empty state
                  ref
                      .read(usernameSearchControllerProvider.notifier)
                      .search(value);
                },
                decoration: InputDecoration(
                  prefixIcon:
                      const Icon(Icons.search, color: AppColors.outline),
                  suffixIcon: hasQuery
                      ? IconButton(
                          icon: const Icon(Icons.close,
                              color: AppColors.outline),
                          onPressed: () {
                            _controller.clear();
                            setState(() {});
                            ref
                                .read(usernameSearchControllerProvider.notifier)
                                .search('');
                          },
                        )
                      : null,
                  hintText: 'Search by username',
                  hintStyle: TextStyle(
                    color: AppColors.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 4,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: !hasQuery
                ? _EmptyState(
                    icon: Icons.person_search_outlined,
                    title: 'Search for people',
                    subtitle: 'Find friends on Wisp by their username.',
                  )
                : resultsAsync.when(
                    data: (results) {
                      if (results.isEmpty) {
                        return const _EmptyState(
                          icon: Icons.search_off_rounded,
                          title: 'No users found',
                          subtitle: 'Try searching for a different username.',
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.pageMargin,
                        ),
                        itemCount: results.length,
                        separatorBuilder: (_, __) => const Divider(
                          color: AppColors.outlineVariant,
                          height: 1,
                        ),
                        itemBuilder: (context, index) {
                          final profile = results[index];
                          final isStarting =
                              _startingConversationForUserId == profile.id;
                          return _UserResultTile(
                            profile: profile,
                            isLoading: isStarting,
                            onTap: isStarting
                                ? null
                                : () => _startChat(profile),
                          );
                        },
                      );
                    },
                    loading: () => const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    error: (e, _) => _EmptyState(
                      icon: Icons.error_outline,
                      title: 'Something went wrong',
                      subtitle: e.toString(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _UserResultTile extends StatelessWidget {
  const _UserResultTile({
    required this.profile,
    required this.onTap,
    required this.isLoading,
  });

  final Profile profile;
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final nameForInitial = (profile.displayName?.isNotEmpty == true
        ? profile.displayName!
        : profile.username);
    final initials = nameForInitial.substring(0, 1).toUpperCase();

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: AppColors.surfaceContainerHigh,
        child: Text(
          initials,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(color: AppColors.primary),
        ),
      ),
      title: Text(
        '@${profile.username}',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      subtitle: profile.displayName != null
          ? Text(
              profile.displayName!,
              style: Theme.of(context).textTheme.bodyMedium,
            )
          : null,
      trailing: isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chat_bubble_outline, color: AppColors.primary),
      onTap: onTap,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppColors.outline),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
