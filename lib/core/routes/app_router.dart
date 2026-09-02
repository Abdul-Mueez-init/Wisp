import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Session;

import 'app_shell.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/login_signup_screen.dart';
import '../../features/auth/screens/onboarding_screen.dart';
import '../../features/calls/screens/call_screen.dart';
import '../../features/chat/screens/chat_detail_screen.dart';
import '../../features/contacts/screens/user_search_screen.dart';
import '../../features/groups/screens/group_creation_screen.dart';
import '../../features/groups/screens/group_members_screen.dart';
import '../../features/profile/providers/profile_provider.dart';
import '../../features/stories/screens/story_capture_screen.dart';
import '../../features/stories/screens/story_viewer_screen.dart';
import '../../models/conversation.dart';
import '../../models/profile.dart';

/// BUGFIX (Home tab going blank + "Another exception was thrown" on
/// interaction): this used to be a plain `Provider<GoRouter>` that
/// called `ref.watch(currentSessionProvider)` /
/// `ref.watch(currentProfileProvider)` directly inside the provider
/// body. That meant *any* emission from either — not just a real
/// login/logout, but also a Supabase `TOKEN_REFRESHED` event (which
/// `_PresenceLifecycle` in main.dart deliberately triggers on every
/// app resume via `refreshSessionIfNeeded()`) — made Riverpod recompute
/// the whole provider from scratch, handing `MaterialApp.router` a
/// brand-new `GoRouter` instance. A new `GoRouter` means a new internal
/// `Navigator`/`GlobalKey`, so the *entire* routed widget tree
/// (AppShell, its bottom nav, the current screen) was being torn down
/// and rebuilt out from under whatever was on screen — including
/// mid-gesture, e.g. right after backgrounding/foregrounding the app.
/// That's what produced a blank Home tab and a "null" exception the
/// moment you touched the screen afterward.
///
/// Fix: build the `GoRouter` exactly ONCE per app lifetime. Auth/
/// profile-driven redirects still work exactly as before, but now
/// react via `refreshListenable` (which just asks GoRouter to re-run
/// `redirect` in place) instead of the router object itself being
/// thrown away and recreated.
final routerProvider = Provider<GoRouter>((ref) {
  final refreshListenable = _RouterRefreshListenable(ref);
  ref.onDispose(refreshListenable.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      // `ref.read` (not `watch`) — this callback already re-runs on its
      // own every time `refreshListenable` fires, so it doesn't need to
      // (and shouldn't) also make the surrounding provider reactive.
      final session = ref.read(currentSessionProvider);
      final isAuthenticated = session != null;
      final profileAsync = isAuthenticated
          ? ref.read(currentProfileProvider)
          : const AsyncValue<dynamic>.data(null);

      final loggingIn = state.matchedLocation == '/login';
      final onboarding = state.matchedLocation == '/onboarding';

      if (!isAuthenticated) {
        return loggingIn ? null : '/login';
      }
      if (loggingIn) return '/';

      return profileAsync.when(
        data: (profile) {
          final hasProfile = profile != null;
          if (!hasProfile && !onboarding) return '/onboarding';
          if (hasProfile && onboarding) return '/';
          return null;
        },
        loading: () => null,
        error: (_, __) => null,
      );
    },
    routes: [
      GoRoute(
        // Batch 6b: was a bootstrap placeholder, now the real
        // bottom-nav shell (Chats/Status/Calls/Settings).
        path: '/',
        builder: (context, state) => const AppShell(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginSignupScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/search',
        builder: (context, state) => const UserSearchScreen(),
      ),
      GoRoute(
        path: '/group/new',
        builder: (context, state) => const GroupCreationScreen(),
      ),
      GoRoute(
        path: '/group/:id/members',
        builder: (context, state) {
          final conversationId = state.pathParameters['id']!;
          return GroupMembersScreen(conversationId: conversationId);
        },
      ),
      GoRoute(
        path: '/chat/:id',
        builder: (context, state) {
          final conversationId = state.pathParameters['id']!;
          final extra = state.extra;
          final otherProfile = extra is Profile ? extra : null;
          final groupConversation = extra is Conversation ? extra : null;

          // Phase 8 — set only by the Chat List's pinned "Wisp AI"
          // tile after `findOrCreateAiConversation`; a query param
          // rather than `extra` since `extra` is already typed to
          // distinguish Profile vs Conversation above.
          final isAiConversation = state.uri.queryParameters['ai'] == 'true';

          return ChatDetailScreen(
            conversationId: conversationId,
            otherProfile: otherProfile,
            groupConversation: groupConversation,
            isAiConversation: isAiConversation,
          );
        },
      ),
      GoRoute(
        // Phase 10 — single screen covering ringing/connecting/active;
        // reads all its state from callControllerProvider, so it takes
        // no path params/extra. Pushed either by the caller (chat
        // detail's call icons) or automatically for the callee (see
        // _IncomingCallListener in main.dart).
        path: '/call',
        builder: (context, state) => const CallScreen(),
      ),
      GoRoute(
        // Batch 6b: launched from the Status tab's "My status" row.
        path: '/status/new',
        builder: (context, state) => const StoryCaptureScreen(),
      ),
      GoRoute(
        // Batch 6c: fullscreen story viewer, opened from the Status tab.
        path: '/status/view',
        builder: (context, state) {
          final args = state.extra as StoryViewerArgs;
          return StoryViewerScreen(
            groups: args.groups,
            initialIndex: args.initialIndex,
          );
        },
      ),
    ],
  );
});

/// Bridges Riverpod state into a plain `Listenable` GoRouter can watch
/// via `refreshListenable`, so `redirect` re-runs whenever auth/profile
/// state changes — without the `GoRouter` object (and its Navigator)
/// ever being torn down and recreated. See the doc comment on
/// `routerProvider` above for why that distinction matters.
class _RouterRefreshListenable extends ChangeNotifier {
  _RouterRefreshListenable(Ref ref) {
    _subs = [
      ref.listen<Session?>(
        currentSessionProvider,
        (_, __) => notifyListeners(),
      ),
      ref.listen<AsyncValue<Profile?>>(
        currentProfileProvider,
        (_, __) => notifyListeners(),
      ),
    ];
  }

  late final List<ProviderSubscription> _subs;

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.close();
    }
    super.dispose();
  }
}
