// lib/core/routes/app_shell.dart
import 'package:flutter/material.dart';

import '../../features/calls/screens/calls_tab_screen.dart';
import '../../features/chat/screens/chat_list_screen.dart';
import '../../features/profile/screens/profile_settings_screen.dart';
import '../../features/stories/screens/status_list_screen.dart';
import '../theme/app_theme.dart';

/// Bottom-nav scaffold added in Batch 6b — per the Phase 6 handoff doc,
/// both the chat list and the Status screen assumed a persistent
/// bottom nav (Chats/Status/Calls/Settings) that didn't exist. All four
/// tabs are now real screens (Batch 10c closes out Calls, the last
/// remaining stub — previously "coming later" per rules.md Rule 2).
/// Replaces the old bootstrap screen as the `/` route.
///
/// Phase 2 fix (wisp_fixes_handoff.md, Finding B): `_tabs` used to be a
/// `static const` list, so all four tab screens — including
/// `CallsTabScreen`, which opens a Realtime `.stream()` subscription the
/// moment it's built — were constructed eagerly at launch, before the
/// Realtime socket had necessarily finished its own auth handshake even
/// though `currentSessionProvider` already had a cached session
/// synchronously. That race, not an RLS problem, is what produced the
/// "Could not load call history" flash on cold launch. Fix: each
/// non-landing tab is now only ever constructed the first time it's
/// actually selected. `IndexedStack` still keeps every *built* tab's
/// state alive when switching away from it — only the up-front eager
/// construction of tabs the user hasn't opened yet is gone.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  // Which tabs have been built at least once. Chats (index 0) is the
  // landing tab, so it's built immediately same as before; Status,
  // Calls, and Settings are built lazily on first selection.
  final Set<int> _builtIndexes = {0};

  static const _screens = [
    ChatListScreen(),
    StatusListScreen(),
    CallsTabScreen(),
    ProfileSettingsScreen(),
  ];

  void _onDestinationSelected(int i) {
    setState(() {
      _index = i;
      _builtIndexes.add(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          for (var i = 0; i < _screens.length; i++)
            _builtIndexes.contains(i) ? _screens[i] : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _onDestinationSelected,
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
