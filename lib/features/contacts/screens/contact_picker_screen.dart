// lib/features/contacts/screens/contact_picker_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/profile.dart';
import '../providers/contacts_provider.dart';

/// Batch 5d — username search reused as a picker: same
/// `usernameSearchControllerProvider` as [UserSearchScreen], but
/// tapping a result pops this screen with the chosen [Profile] instead
/// of starting a chat. Pushed as a plain modal route (not a go_router
/// path) from `chat_input_bar.dart`'s attachment sheet — same
/// precedent as `VideoPlayerView`, since this is a transient picker,
/// not a primary navigation destination.
class ContactPickerScreen extends ConsumerStatefulWidget {
  const ContactPickerScreen({super.key});

  @override
  ConsumerState<ContactPickerScreen> createState() =>
      _ContactPickerScreenState();
}

class _ContactPickerScreenState extends ConsumerState<ContactPickerScreen> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    // usernameSearchControllerProvider is shared with UserSearchScreen —
    // clear any stale results from a prior visit so this picker always
    // opens fresh.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(usernameSearchControllerProvider.notifier).search('');
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resultsAsync = ref.watch(usernameSearchControllerProvider);
    final hasQuery = _controller.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.backgroundBase,
      appBar: AppBar(
        title: const Text('Share a contact'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
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
                  setState(() {});
                  ref
                      .read(usernameSearchControllerProvider.notifier)
                      .search(value);
                },
                decoration: InputDecoration(
                  prefixIcon:
                      const Icon(Icons.search, color: AppColors.outline),
                  suffixIcon: hasQuery
                      ? IconButton(
                          icon:
                              const Icon(Icons.close, color: AppColors.outline),
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
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        'Search for a Wisp user to share their contact.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  )
                : resultsAsync.when(
                    data: (results) {
                      if (results.isEmpty) {
                        return Center(
                          child: Text(
                            'No users found',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
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
                          final nameForInitial =
                              profile.displayName?.isNotEmpty == true
                                  ? profile.displayName!
                                  : profile.username;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 24,
                              backgroundColor: AppColors.surfaceContainerHigh,
                              child: Text(
                                nameForInitial.substring(0, 1).toUpperCase(),
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
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  )
                                : null,
                            trailing: const Icon(Icons.chevron_right,
                                color: AppColors.outline),
                            onTap: () => Navigator.of(context).pop(profile),
                          );
                        },
                      );
                    },
                    loading: () => const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    error: (e, _) => Center(
                      child: Text(
                        'Something went wrong',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
