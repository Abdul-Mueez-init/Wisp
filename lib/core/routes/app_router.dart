import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/login_signup_screen.dart';
import '../../features/auth/screens/onboarding_screen.dart';
import '../../features/chat/screens/chat_detail_screen.dart';
import '../../features/contacts/screens/user_search_screen.dart';
import '../../features/groups/screens/group_creation_screen.dart';
import '../../features/groups/screens/group_members_screen.dart';
import '../../features/profile/providers/profile_provider.dart';
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
        path: '/',
        builder: (context, state) => const _BootstrapScreen(),
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
    ],
  );
});

class _BootstrapScreen extends ConsumerWidget {
  const _BootstrapScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Wisp', style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 8),
            profile.when(
              data: (p) => Text(
                p != null ? 'Signed in as @${p.username}' : 'Loading profile…',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              loading: () => const CircularProgressIndicator(strokeWidth: 2),
              error: (e, _) =>
                  Text('$e', style: const TextStyle(color: AppColors.error)),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => GoRouter.of(context).push('/search'),
              icon: const Icon(Icons.person_search_outlined),
              label: const Text('Find people'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => GoRouter.of(context).push('/group/new'),
              icon: const Icon(Icons.groups_outlined),
              label: const Text('New group'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).signOut(),
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}
