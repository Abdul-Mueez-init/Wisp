// lib/core/routes/app_shell.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/chat/screens/chat_list_screen.dart';
import '../../features/profile/providers/profile_provider.dart';
import '../../features/stories/screens/status_list_screen.dart';
import '../theme/app_theme.dart';

/// Bottom-nav scaffold added in Batch 6b — per the Phase 6 handoff doc,
/// both the chat list and the Status screen assumed a persistent
/// bottom nav (Chats/Status/Calls/Settings) that didn't exist. Chats
/// and Status are wired for real; Calls and Settings are deliberately
/// thin "coming later" stubs, not full screens — per rules.md Rule 2,
/// a stub that plainly says what's missing is fine, a fake populated
/// screen isn't. Replaces the old bootstrap screen as the `/` route.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _tabs = [
    ChatListScreen(),
    StatusListScreen(),
    _CallsStubScreen(),
    _SettingsStubScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: AppColors.surfaceContainerLow,
        indicatorColor: AppColors.primaryContainer,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble, color: AppColors.primary),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.donut_large_outlined),
            selectedIcon: Icon(Icons.donut_large, color: AppColors.primary),
            label: 'Status',
          ),
          NavigationDestination(
            icon: Icon(Icons.call_outlined),
            selectedIcon: Icon(Icons.call, color: AppColors.primary),
            label: 'Calls',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings, color: AppColors.primary),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _CallsStubScreen extends StatelessWidget {
  const _CallsStubScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Calls')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.pageMargin),
          child: Text(
            'Audio and video calling lands in Phase 10 — WebRTC + '
            'Supabase Realtime signaling, per plan.md.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ),
    );
  }
}

/// Real (if minimal) functionality, not a fake screen — carries over
/// the sign-out action the old bootstrap screen had, since replacing
/// it with AppShell can't quietly drop the only way to sign out.
/// design.md lists a full "Profile/Settings" Stitch screen as locked
/// and safe to build against — this stub is a placeholder until that
/// gets built out, not a redesign of it.
class _SettingsStubScreen extends ConsumerWidget {
  const _SettingsStubScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentProfileProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.pageMargin),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            profileAsync.when(
              data: (p) => Text(
                p != null ? '@${p.username}' : 'Not signed in',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              loading: () => const CircularProgressIndicator(strokeWidth: 2),
              error: (e, _) =>
                  Text('$e', style: const TextStyle(color: AppColors.error)),
            ),
            const SizedBox(height: 12),
            Text(
              'Full profile & settings (avatar, display name, preferred '
              'language) is one of design.md\'s locked screens, not yet '
              'built out — coming with the rest of the settings work.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const Spacer(),
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
      ),
    );
  }
}
