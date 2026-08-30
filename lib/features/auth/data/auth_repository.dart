import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/failure.dart';

/// All Supabase Auth calls go through here (rules.md Rule 8 pattern
/// extended to auth, not just AI). Feature code/UI never touches
/// `Supabase.instance.client.auth` directly.
class AuthRepository {
  AuthRepository(this._client);
  final SupabaseClient _client;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;
  Session? get currentSession => _client.auth.currentSession;
  User? get currentUser => _client.auth.currentUser;

  /// supabase_flutter's own auto-refresh timer can be throttled while the
  /// app is backgrounded (Android Doze, iOS suspension), so a long
  /// background period can leave `currentSession` holding an
  /// already-expired access token in memory. That's what surfaces as
  /// `InvalidJWTToken: Token has expired` on the next Realtime channel
  /// subscribe attempt — the channel authenticates with whatever token is
  /// currently in the session, stale or not. Called from the app-resume
  /// hook (`main.dart`'s `_PresenceLifecycleState`) before anything
  /// realtime-related reconnects, so the token is forced fresh first.
  Future<void> refreshSessionIfNeeded() async {
    final session = _client.auth.currentSession;
    final expiresAt = session?.expiresAt;
    if (session == null || expiresAt == null) return;
    final expiresAtDate = DateTime.fromMillisecondsSinceEpoch(
      expiresAt * 1000,
    );
    if (DateTime.now()
        .isBefore(expiresAtDate.subtract(const Duration(seconds: 30)))) {
      return;
    }
    try {
      await _client.auth.refreshSession();
    } on AuthException catch (e) {
      throw AuthFailure(e.message);
    }
  }

  Future<void> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final response =
          await _client.auth.signUp(email: email, password: password);
      if (response.user == null) {
        throw const AuthFailure(
          'Sign up did not return a user. Please try again.',
        );
      }
    } on AuthException catch (e) {
      throw AuthFailure(e.message);
    } on AuthFailure {
      rethrow;
    } catch (e) {
      throw AuthFailure('Unexpected error during sign up: $e');
    }
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth
          .signInWithPassword(email: email, password: password);
      if (response.user == null) {
        throw const AuthFailure(
          'Sign in did not return a user. Check your credentials.',
        );
      }
    } on AuthException catch (e) {
      throw AuthFailure(e.message);
    } on AuthFailure {
      rethrow;
    } catch (e) {
      throw AuthFailure('Unexpected error during sign in: $e');
    }
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } on AuthException catch (e) {
      throw AuthFailure(e.message);
    }
  }

  /// Whether a `profiles` row already exists for this user — the router
  /// (next batch) will use this to decide onboarding vs. straight into
  /// the app. Exposed now so the repository contract is settled before
  /// the onboarding screens are built on top of it.
  Future<bool> hasCompletedProfile(String userId) async {
    try {
      final row = await _client
          .from('profiles')
          .select('id')
          .eq('id', userId)
          .maybeSingle();
      return row != null;
    } on PostgrestException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }
}
