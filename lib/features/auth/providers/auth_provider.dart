import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../config/supabase_config.dart';
import '../data/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(SupabaseConfig.client);
});

/// Raw Supabase auth-state stream (SIGNED_IN, SIGNED_OUT, TOKEN_REFRESHED...).
final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

/// Current session derived from the stream, with the *existing* session
/// as a synchronous fallback so the router (next batch) doesn't flash a
/// loading state on first frame before the stream emits.
final currentSessionProvider = Provider<Session?>((ref) {
  final authState = ref.watch(authStateChangesProvider);
  return authState.maybeWhen(
    data: (state) => state.session,
    orElse: () => ref.read(authRepositoryProvider).currentSession,
  );
});

/// One-off auth actions (sign in / sign up / sign out) per
/// architecture.md's "AsyncNotifier for actions" rule.
class AuthController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {
    // No-op initial state — this notifier only tracks action-in-flight status.
  }

  Future<void> signIn({required String email, required String password}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).signInWithEmail(
            email: email,
            password: password,
          ),
    );
  }

  Future<void> signUp({required String email, required String password}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).signUpWithEmail(
            email: email,
            password: password,
          ),
    );
  }

  Future<void> signOut() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).signOut(),
    );
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, void>(
  AuthController.new,
);
