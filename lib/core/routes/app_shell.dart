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
    CallsTabScreen(),
    ProfileSettingsScreen(),
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
