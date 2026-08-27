import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app_shell.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/login_signup_screen.dart';
import '../../features/auth/screens/onboarding_screen.dart';
import '../../features/chat/screens/chat_detail_screen.dart';
import '../../features/contacts/screens/user_search_screen.dart';
import '../../features/groups/screens/group_creation_screen.dart';
import '../../features/groups/screens/group_members_screen.dart';
import '../../features/profile/providers/profile_provider.dart';
import '../../features/stories/screens/story_capture_screen.dart';
import '../../features/stories/screens/story_viewer_screen.dart';
import '../../models/conversation.dart';
import '../../models/profile.dart';

/// Router as a Riverpod provider so it can watch auth/profile state and
/// redirect accordingly.
final routerProvider = Provider<GoRouter>((ref) {
  final session = ref.watch(currentSessionProvider);
  final isAuthenticated = session != null;
  final profileAsync = isAuthenticated
      ? ref.watch(currentProfileProvider)
      : const AsyncValue<dynamic>.data(null);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
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
          return ChatDetailScreen(
            conversationId: conversationId,
            otherProfile: otherProfile,
            groupConversation: groupConversation,
          );
        },
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
