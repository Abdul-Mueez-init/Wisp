import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/supabase_config.dart';
import '../../../core/errors/failure.dart';
import '../../../models/profile.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/profile_repository.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(SupabaseConfig.client);
});

/// The signed-in user's own profile row, or null if onboarding hasn't
/// been completed yet. The router watches this to decide onboarding
/// vs. straight-into-app redirects, and it doubles as the app-wide
/// "my profile" source of truth for later phases (chat, settings).
final currentProfileProvider =
    FutureProvider.autoDispose<Profile?>((ref) async {
  final session = ref.watch(currentSessionProvider);
  if (session == null) return null;
  return ref.read(profileRepositoryProvider).fetchProfile(session.user.id);
});

/// Handles the final onboarding submission: optional avatar upload,
/// then the `profiles` row insert. Per architecture.md, this action
/// logic lives in a Notifier, not in the onboarding widgets.
class OnboardingController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> completeOnboarding({
    required String username,
    String? displayName,
    Uint8List? avatarBytes,
    String? avatarExt,
    required String preferredLanguage,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final session = ref.read(currentSessionProvider);
      if (session == null) {
        throw const AuthFailure('No authenticated session found.');
      }
      final repo = ref.read(profileRepositoryProvider);

      String? avatarPath;
      if (avatarBytes != null && avatarExt != null) {
        avatarPath = await repo.uploadAvatar(
          userId: session.user.id,
          bytes: avatarBytes,
          fileExt: avatarExt,
        );
      }

      await repo.createProfile(
        id: session.user.id,
        username: username,
        displayName: (displayName == null || displayName.trim().isEmpty)
            ? null
            : displayName.trim(),
        avatarPath: avatarPath,
        preferredLanguage: preferredLanguage,
      );

      // Invalidate so currentProfileProvider refetches — the router
      // (watching this same provider) picks up the change and redirects
      // out of /onboarding automatically.
      ref.invalidate(currentProfileProvider);
    });
  }
}

final onboardingControllerProvider =
    AsyncNotifierProvider<OnboardingController, void>(OnboardingController.new);
