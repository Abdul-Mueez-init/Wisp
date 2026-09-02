// lib/core/constants/layout_constants.dart

/// Reserved vertical clearance for `AppShell`'s floating glass nav bar
/// (`_PillNavBar` in `core/routes/app_shell.dart`).
///
/// This is **not** a design.md token — it's a derived layout number
/// (pill height 80 — tall enough for the icon+label pill's own vertical
/// padding around the two stacked lines — + its own bottom safe-area
/// margin 12 + a small visual gap 12 = 104) needed because `AppShell`'s
/// `Scaffold` now runs `extendBody: true` so the floating pill can show
/// real (blurred) content behind it, Jazz-World-reference style. Every
/// tab screen nested inside `AppShell` (`ChatListScreen`,
/// `StatusListScreen`, `CallsTabScreen`, `ProfileSettingsScreen`) needs
/// this exact number as trailing scroll padding so their last item
/// lands just above the pill instead of underneath it. Kept as one
/// shared constant instead of a hardcoded number in each screen so the
/// two stay in sync if the pill's own height/margins ever change.
const double kFloatingNavClearance = 104.0;
