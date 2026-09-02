// lib/core/routes/app_shell.dart
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../features/calls/screens/calls_tab_screen.dart';
import '../../features/chat/screens/chat_list_screen.dart';
import '../../features/profile/screens/profile_settings_screen.dart';
import '../../features/stories/screens/status_list_screen.dart';
import '../constants/layout_constants.dart';
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
///
/// Jazz-World glass pass (this session) — `extendBody: true` added so
/// the pill nav shows real, blurred app content behind it instead of a
/// solid strip (see `_PillNavBar`'s doc comment). The only change in
/// *this* build method beyond that flag is the `MediaQuery` wrapper
/// around `IndexedStack`, which pads every tab's ambient bottom safe
/// area by `kFloatingNavClearance` so nested Scaffolds/FABs
/// automatically clear the floating pill. `_index`/`_builtIndexes`
/// selection logic is still untouched.
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
    final mq = MediaQuery.of(context);
    return Scaffold(
      // `extendBody: true` is what makes the pill nav genuinely glass —
      // without it, the outer Scaffold reserves a solid, opaque strip
      // for `bottomNavigationBar` and there's nothing real behind the
      // pill to blur, which is why the previous pass could only fake a
      // frosted look. With it, each tab's real content now runs the
      // full height of the screen, underneath the floating pill.
      //
      // That means each tab screen needs to reserve `kFloatingNavClearance`
      // of trailing scroll space itself so its last item isn't
      // permanently hidden under the pill — done via the MediaQuery
      // override below, which every nested Scaffold (no bottomNavigationBar
      // of its own) and its FloatingActionButton already respect
      // automatically, plus an explicit bottom-padding line added to
      // each of the four tab screens' own scrollables (chat_list_screen.dart,
      // status_list_screen.dart, calls_tab_screen.dart,
      // profile_settings_screen.dart) so their content — not just the
      // FAB — clears the glass pill correctly.
      extendBody: true,
      body: MediaQuery(
        data: mq.copyWith(
          padding: mq.padding.copyWith(
            bottom: mq.padding.bottom + kFloatingNavClearance,
          ),
        ),
        child: IndexedStack(
          index: _index,
          children: [
            for (var i = 0; i < _screens.length; i++)
              _builtIndexes.contains(i) ? _screens[i] : const SizedBox.shrink(),
          ],
        ),
      ),
      bottomNavigationBar: _PillNavBar(
        selectedIndex: _index,
        onSelect: _onDestinationSelected,
      ),
    );
  }
}

/// Floating pill-shaped nav bar (Phase 4, restyled across three
/// Jazz-World passes). A rounded, frosted-glass container floating
/// above the page margin. The outer shape (floating stadium, full
/// corner radius, glass blur) is the hand-built `Container`/`ClipRRect`/
/// `BackdropFilter` stack from the earlier pass — untouched here.
///
/// This pass fixes what the stock Material 3 `NavigationBar` (previous
/// attempt) structurally can't do: in the reference, the selected tab's
/// highlight is one shape that **encloses both the icon and its label
/// together** (icon on top, label underneath, both inside the same
/// rounded highlight) — not a circle behind the icon with the label
/// sitting outside/below it. `NavigationBar`'s `indicatorShape` only
/// ever wraps the icon slot by design; there's no supported way to
/// stretch that indicator down to cover the label too. So the items are
/// back to a small hand-built `_PillNavItem`, this time laid out as an
/// icon-over-label `Column` (not the very first pass's icon-beside-
/// label `Row`, which is what caused the earlier overflow bug) — same
/// available width as before, just stacked instead of side-by-side, so
/// there's no overflow risk reintroduced.
///
/// Note on "circular": the highlight here is a rounded rectangle
/// (`AppRadius.xl`, 16px corners) sized to fit its content
/// (`mainAxisSize.min`, not stretched to the cell's full width) rather
/// than a literal circle — a true circle can't cleanly contain a
/// two-line, non-square icon+label group without a lot of dead space
/// around it. Visually this reads as the same soft, all-corners-rounded
/// "blob" the reference uses; it just isn't mathematically circular,
/// which a plain `CircleBorder` couldn't be while still holding text.
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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.full),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              height: 80,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.surfaceContainerLow.withValues(alpha: 0.78),
                    AppColors.surfaceContainerLowest.withValues(alpha: 0.88),
                  ],
                ),
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(
                  color: AppColors.outlineVariant.withValues(alpha: 0.22),
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
      child: Center(
        // `Center` + `mainAxisSize: min` below (not `Expanded`'s full
        // cell width) so the highlight hugs just the icon+label content,
        // matching the reference's snug pill rather than stretching
        // edge-to-edge across this tab's quarter of the bar.
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? item.selectedIcon : item.icon,
                size: 20,
                color: selected ? AppColors.onPrimary : AppColors.outline,
              ),
              const SizedBox(height: 3),
              Text(
                item.label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: selected ? AppColors.onPrimary : AppColors.outline,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
