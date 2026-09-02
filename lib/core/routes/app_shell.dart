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
///
/// Phase 4 (wisp_fixes_handoff.md item 4) — the bottom nav itself was
/// rebuilt from Material's stock `NavigationBar` into a floating pill
/// shape matching the Jazz-World reference screenshot's shape language
/// (rounded container, filled active-state background). Layout/shape
/// change only, built entirely from tokens already in app_theme.dart —
/// no new colors, and the `_index`/`_builtIndexes`/`IndexedStack` logic
/// above is untouched.
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
      bottomNavigationBar: _PillNavBar(
        selectedIndex: _index,
        onSelect: _onDestinationSelected,
      ),
    );
  }
}

/// Floating pill-shaped nav bar (Phase 4). A rounded container floating
/// above the page margin, each destination rendered by [_PillNavItem];
/// the selected one grows an inline pill of its own
/// (`AppColors.primaryContainer`, same "Moderate Green" fill design.md
/// uses for sent bubbles and primary buttons) around its icon + label,
/// mirroring the Jazz-World reference's active-tab treatment.
class _PillNavBar extends StatelessWidget {
  const _PillNavBar({required this.selectedIndex, required this.onSelect});

  final int selectedIndex;
  final ValueChanged<int> onSelect;

  static const _items = [
    (
      icon: Icons.chat_bubble_outline,
      selectedIcon: Icons.chat_bubble,
      label: 'Chats',
    ),
    (
      icon: Icons.donut_large_outlined,
      selectedIcon: Icons.donut_large,
      label: 'Status',
    ),
    (icon: Icons.call_outlined, selectedIcon: Icons.call, label: 'Calls'),
    (
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: 'Settings',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageMargin),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: _PillNavItem(
                    item: _items[i],
                    selected: i == selectedIndex,
                    onTap: () => onSelect(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillNavItem extends StatelessWidget {
  const _PillNavItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final ({IconData icon, IconData selectedIcon, String label}) item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? item.selectedIcon : item.icon,
              size: 22,
              color: selected ? AppColors.primary : AppColors.outline,
            ),
            // BUGFIX (RenderFlex overflow at app_shell.dart:175): this
            // Row sits inside `Expanded` (one quarter of the pill bar's
            // width, per `_PillNavBar`), but `mainAxisSize: min` still
            // laid the label `Text` out at its own natural/unconstrained
            // width. On a narrow screen that quarter-width can be as
            // little as ~50px, which "Settings"/"Status" at label-medium
            // simply don't fit in alongside the icon — nothing was
            // there to shrink it, so it overflowed by a fixed pixel
            // amount regardless of device width. Wrapping the label in
            // `Flexible` + `TextOverflow.ellipsis` lets it claim
            // whatever width is actually left after the icon, and
            // gracefully truncate instead of overflowing on anything
            // narrower than that.
            if (selected) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  item.label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
