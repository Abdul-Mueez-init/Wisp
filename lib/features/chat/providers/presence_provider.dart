import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/supabase_config.dart';
import '../../../models/profile.dart';
import '../../auth/providers/auth_provider.dart';
import '../../profile/providers/profile_provider.dart';
import '../data/presence_repository.dart';

final presenceRepositoryProvider = Provider<PresenceRepository>((ref) {
  return PresenceRepository(SupabaseConfig.client);
});

/// Perf fix (WISP_PERFORMANCE_HANDOFF.md §10) — the single realtime
/// source feeding presence app-wide, replacing what used to be one
/// `watchProfileProvider(userId)` subscription per user shown on
/// screen (one for the open chat's app bar, plus one per direct row
/// in the chat list — scaling linearly with conversation count).
final allProfilesStreamProvider = StreamProvider<List<Profile>>((ref) {
  return ref.read(profileRepositoryProvider).watchAllProfiles();
});

/// Indexed once per emission, same pattern as `messageStatusByIdProvider`
/// (Phase A). Callers use `.select` against this map (e.g.
/// `presenceByIdProvider.select((m) => m[userId]?.isOnline)`) so a
/// presence change for one user only rebuilds the specific row/widget
/// showing that user, not every row and not the whole screen.
final presenceByIdProvider = Provider<Map<String, Profile>>((ref) {
  final profiles = ref.watch(allProfilesStreamProvider).value ?? const [];
  return {for (final p in profiles) p.id: p};
});

/// Drives *this device's* own online/offline presence: joins the shared
/// presence channel and writes the corresponding `profiles.is_online`
/// state. Started/stopped by the app-lifecycle observer in main.dart in
/// response to auth transitions and foreground/background transitions
/// — no screen/widget calls this directly.
class PresenceController {
  PresenceController(this._ref);
  final Ref _ref;

  Future<void> goOnline() async {
    final userId = _ref.read(currentSessionProvider)?.user.id;
    if (userId == null) return;
    try {
      await _ref.read(presenceRepositoryProvider).track(userId);
      await _ref
          .read(profileRepositoryProvider)
          .setOnlineStatus(userId: userId, isOnline: true);
    } catch (_) {
      // Best-effort: presence is a live nicety, not a correctness
      // requirement — a failed flip here shouldn't crash the app or
      // surface an error to the user (rules.md Rule 2 still applies to
      // the *feature's* own actions, e.g. sending a message; this is
      // background sync).
    }
  }

  Future<void> goOffline() async {
    final userId = _ref.read(currentSessionProvider)?.user.id;
    try {
      await _ref.read(presenceRepositoryProvider).untrack();
      if (userId == null) return;
      await _ref
          .read(profileRepositoryProvider)
          .setOnlineStatus(userId: userId, isOnline: false);
    } catch (_) {
      // See goOnline().
    }
  }
}

final presenceControllerProvider = Provider<PresenceController>((ref) {
  return PresenceController(ref);
});
