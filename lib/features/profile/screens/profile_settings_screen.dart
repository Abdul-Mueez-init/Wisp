// lib/features/profile/screens/profile_settings_screen.dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/language_options.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/profile_provider.dart';

/// Real Profile/Settings screen — design.md lists this as one of the
/// 13 locked Stitch screens. Replaces the sign-out-only stub that
/// shipped with AppShell in batch 6b.
///
/// Closes the gap flagged in context.md's Open Issues: avatar, display
/// name, and preferred language were not editable anywhere, and the
/// last of those is a hard dependency for Phase 7 (translation) — this
/// had to land before or alongside Phase 7, not deferred to Phase 11.
///
/// Username is intentionally NOT editable — see the comment on
/// ProfileRepository.updateProfile for why.
class ProfileSettingsScreen extends ConsumerStatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  ConsumerState<ProfileSettingsScreen> createState() =>
      _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends ConsumerState<ProfileSettingsScreen> {
  final _displayNameController = TextEditingController();
  String _selectedLanguage = 'en';
  Uint8List? _newAvatarBytes;
  String? _newAvatarExt;
  bool _prefilled = false;

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _newAvatarBytes = bytes;
      _newAvatarExt = picked.path.split('.').last;
    });
  }

  Future<void> _save() async {
    final success =
        await ref.read(updateProfileControllerProvider.notifier).updateProfile(
              displayName: _displayNameController.text,
              avatarBytes: _newAvatarBytes,
              avatarExt: _newAvatarExt,
              preferredLanguage: _selectedLanguage,
            );
    if (!mounted) return;
    if (success) {
      setState(() {
        _newAvatarBytes = null;
        _newAvatarExt = null;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Profile updated.')));
    } else {
      final failure = ref.read(updateProfileControllerProvider).error;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$failure')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentProfileProvider);
    final saving = ref.watch(updateProfileControllerProvider).isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: profileAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(
          child: Text('$e', style: const TextStyle(color: AppColors.error)),
        ),
        data: (profile) {
          if (profile == null) {
            return const Center(child: Text('Not signed in'));
          }
          // Prefill once from the loaded profile — don't stomp on an
          // in-progress edit every time this provider rebuilds (e.g.
          // right after _save()'s own invalidate() call).
          if (!_prefilled) {
            _displayNameController.text = profile.displayName ?? '';
            _selectedLanguage = profile.preferredLanguage;
            _prefilled = true;
          }

          final existingAvatarUrl = profile.avatarUrl != null
              ? ref
                  .read(profileRepositoryProvider)
                  .resolveAvatarUrl(profile.avatarUrl!)
              : null;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.pageMargin),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: GestureDetector(
                    onTap: _pickAvatar,
                    child: Stack(
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: const BoxDecoration(
                            color: AppColors.surfaceRaised,
                            shape: BoxShape.circle,
                          ),
                          child: ClipOval(
                            child: _newAvatarBytes != null
                                ? Image.memory(_newAvatarBytes!,
                                    fit: BoxFit.cover)
                                : existingAvatarUrl != null
                                    ? Image.network(existingAvatarUrl,
                                        fit: BoxFit.cover)
                                    : const Icon(Icons.person_outline,
                                        color: AppColors.outline, size: 36),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primaryContainer,
                            ),
                            child: const Icon(Icons.camera_alt_outlined,
                                size: 16, color: AppColors.cream),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text('@${profile.username}',
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
                const SizedBox(height: AppSpacing.stackDefault * 2),
                Text('Display name',
                    style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 6),
                TextField(
                  controller: _displayNameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.surfaceRaised,
                    hintText: 'Your name',
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppRadius.buttonInput),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 16),
                  ),
                ),
                const SizedBox(height: 24),
                Text('Preferred language',
                    style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(AppRadius.buttonInput),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _selectedLanguage,
                      dropdownColor: AppColors.surfaceContainerHigh,
                      style: Theme.of(context).textTheme.bodyLarge,
                      icon: const Icon(Icons.keyboard_arrow_down,
                          color: AppColors.outline),
                      items: languageOptions
                          .map((lang) => DropdownMenuItem(
                              value: lang.$1, child: Text(lang.$2)))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedLanguage = value);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This is what your messages get translated into, and '
                  'what non-English messages you send are compared '
                  'against (AI Feature 1, Phase 7).',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: AppSpacing.stackDefault * 2),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: saving ? null : _save,
                    child: saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.cream),
                          )
                        : const Text('Save changes'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        ref.read(authControllerProvider.notifier).signOut(),
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
