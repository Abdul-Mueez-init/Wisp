import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/profile.dart';
import '../../contacts/providers/contacts_provider.dart';
import '../providers/group_provider.dart';

/// Built from design.md tokens directly (no Stitch export for group
/// creation) — reuses the same pill search-field pattern and the
/// debounced `usernameSearchControllerProvider` from Phase 2, per
/// PRD.md section 6: "Any user can create a group and add members."
class GroupCreationScreen extends ConsumerStatefulWidget {
  const GroupCreationScreen({super.key});

  @override
  ConsumerState<GroupCreationScreen> createState() =>
      _GroupCreationScreenState();
}

class _GroupCreationScreenState extends ConsumerState<GroupCreationScreen> {
  final _nameController = TextEditingController();
  final _searchController = TextEditingController();
  final Map<String, Profile> _selected = {};

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _toggle(Profile profile) {
    setState(() {
      if (_selected.containsKey(profile.id)) {
        _selected.remove(profile.id);
      } else {
        _selected[profile.id] = profile;
      }
    });
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _selected.isEmpty) return;

    final conversationId =
        await ref.read(createGroupControllerProvider.notifier).createGroup(
              name: name,
              memberIds: _selected.keys.toList(),
            );

    if (!mounted) return;

    if (conversationId != null) {
      context.go('/chat/$conversationId');
    } else {
      final error = ref.read(createGroupControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error?.toString() ?? 'Could not create group.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final resultsAsync = ref.watch(usernameSearchControllerProvider);
    final creating = ref.watch(createGroupControllerProvider).isLoading;
    final canCreate =
        _nameController.text.trim().isNotEmpty && _selected.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.backgroundBase,
      appBar: AppBar(
        title: const Text('New group'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageMargin,
              12,
              AppSpacing.pageMargin,
              0,
            ),
            child: _PillField(
              controller: _nameController,
              hintText: 'Group name',
              icon: Icons.groups_outlined,
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (_selected.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.pageMargin,
                ),
                itemCount: _selected.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final profile = _selected.values.elementAt(index);
                  return Chip(
                    backgroundColor: AppColors.surfaceRaised,
                    label: Text('@${profile.username}'),
                    labelStyle: Theme.of(context).textTheme.labelMedium,
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => _toggle(profile),
                    side: BorderSide(
                      color: AppColors.outlineVariant.withValues(alpha: 0.3),
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.pageMargin,
            ),
            child: _PillField(
              controller: _searchController,
              hintText: 'Add people by username',
              icon: Icons.search,
              onChanged: (value) => ref
                  .read(usernameSearchControllerProvider.notifier)
                  .search(value),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: resultsAsync.when(
              data: (results) {
                if (_searchController.text.trim().isEmpty) {
                  return Center(
                    child: Text(
                      'Search for people to add.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  );
                }
                if (results.isEmpty) {
                  return Center(
                    child: Text(
                      'No users found.',
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
                    return _SelectableUserTile(
                      profile: profile,
                      selected: _selected.containsKey(profile.id),
                      onTap: () => _toggle(profile),
                    );
                  },
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              error: (e, _) => Center(
                child:
                    Text('$e', style: Theme.of(context).textTheme.bodyMedium),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageMargin,
                8,
                AppSpacing.pageMargin,
                12,
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: canCreate && !creating ? _create : null,
                  child: creating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.cream,
                          ),
                        )
                      : Text(
                          _selected.isEmpty
                              ? 'Create group'
                              : 'Create group (${_selected.length})',
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PillField extends StatelessWidget {
  const _PillField({
    required this.controller,
    required this.hintText,
    required this.icon,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: Theme.of(context).textTheme.bodyLarge,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: AppColors.outline),
          hintText: hintText,
          hintStyle: TextStyle(
            color: AppColors.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        ),
      ),
    );
  }
}

class _SelectableUserTile extends StatelessWidget {
  const _SelectableUserTile({
    required this.profile,
    required this.selected,
    required this.onTap,
  });

  final Profile profile;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final nameForInitial = (profile.displayName?.isNotEmpty == true
        ? profile.displayName!
        : profile.username);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: AppColors.surfaceContainerHigh,
        child: Text(
          nameForInitial.substring(0, 1).toUpperCase(),
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(color: AppColors.primary),
        ),
      ),
      title: Text('@${profile.username}',
          style: Theme.of(context).textTheme.titleMedium),
      subtitle: profile.displayName != null
          ? Text(profile.displayName!,
              style: Theme.of(context).textTheme.bodyMedium)
          : null,
      trailing: Icon(
        selected ? Icons.check_circle : Icons.circle_outlined,
        color: selected ? AppColors.primary : AppColors.outline,
      ),
      onTap: onTap,
    );
  }
}
