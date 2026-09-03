import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/ai_config.dart';
import 'config/supabase_config.dart';
import 'config/webrtc_config.dart';
import 'core/routes/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/calls/providers/call_controller.dart';
import 'features/calls/providers/call_session_state.dart';
import 'features/chat/providers/presence_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: _WispBootstrap()));
}

/// Phase 5 (wisp_fixes_handoff.md item 2) — the branded launch screen.
///
/// Before this phase, `main()` awaited the *entire* init sequence
/// (dotenv → Supabase → AI config → WebRTC config) before ever calling
/// `runApp()` — so Flutter had nothing to paint until all four steps
/// resolved, meaning whatever the OS shows before the first frame (a
/// blank/white window, platform-dependent) was the de facto "splash."
/// This widget flips that: `runApp()` now fires immediately with
/// `_WispBootstrap`, which shows [_SplashScreen] while running that
/// exact same init sequence inside `initState`, then swaps to the real
/// [WispApp] once it resolves. No fixed delay is added anywhere — the
/// splash is on screen for exactly as long as init actually takes, per
/// the phase's acceptance criteria.
///
/// [WispApp] itself can't be built any earlier than this: its
/// `MaterialApp.router` reads `routerProvider`, which watches
/// `currentSessionProvider` — Supabase's auth state — so the real
/// router genuinely cannot exist before `SupabaseConfig.initialize()`
/// resolves. `_SplashScreen` is rendered inside its own minimal
/// `MaterialApp` for exactly that reason: it can't depend on anything
/// `routerProvider` provides.
class _WispBootstrap extends StatefulWidget {
  const _WispBootstrap();

  @override
  State<_WispBootstrap> createState() => _WispBootstrapState();
}

class _WispBootstrapState extends State<_WispBootstrap> {
  late Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = _initialize();
  }

  Future<void> _initialize() async {
    await dotenv.load(fileName: '.env');

    await SupabaseConfig.initialize(
      url: dotenv.env['SUPABASE_URL'] ?? '',
      anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
    );

    AiConfig.initialize(
      geminiApiKey: dotenv.env['GEMINI_API_KEY'] ?? '',
      groqApiKey: dotenv.env['GROQ_API_KEY'] ?? '',
    );

    // Phase 10 — TURN creds optional at first run; STUN-only fallback
    // inside WebrtcConfig keeps calls working before you fill these in.
    WebrtcConfig.initialize(
      turnUrl: dotenv.env['TURN_URL'] ?? '',
      turnUsername: dotenv.env['TURN_USERNAME'] ?? '',
      turnCredential: dotenv.env['TURN_CREDENTIAL'] ?? '',
    );
    // Bugfix (reported: "can't hear the beep sound mid call") — sets up
    // the shared AudioSession once at boot so CallSoundPlayer's ring/
    // dial tone survives WebRTC grabbing the mic later. See
    // WebrtcConfig.configureAudioSession's doc comment.
    await WebrtcConfig.configureAudioSession();
  }

  void _retry() {
    setState(() {
      _initFuture = _initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        // BUGFIX: this used to only branch on `connectionState`, so an
        // init failure (bad/missing .env, unreachable Supabase project,
        // etc.) was silently swallowed — `connectionState` becomes
        // `done` whether the future succeeded OR errored, and the old
        // code fell straight through to `WispApp()` either way. That
        // meant a genuine init failure looked identical, from the
        // user's side, to "the app is just stuck" — no error, no
        // signal, nothing actionable in the UI, only whatever got
        // printed to the terminal. Checking `snapshot.hasError`
        // explicitly here means a real init failure now surfaces as a
        // visible, retryable error screen instead of quietly limping
        // into `WispApp()` with an uninitialized Supabase/AI/WebRTC
        // client underneath it.
        if (snapshot.connectionState != ConnectionState.done) {
          return const _SplashApp();
        }
        if (snapshot.hasError) {
          return _InitErrorApp(
            error: snapshot.error!,
            onRetry: _retry,
          );
        }
        return const WispApp();
      },
    );
  }
}

/// A standalone `MaterialApp` just for the splash frame(s) — deliberately
/// not `MaterialApp.router`, since [WispApp]'s router isn't safe to
/// build yet at this point (see [_WispBootstrap]'s doc comment).
class _SplashApp extends StatelessWidget {
  const _SplashApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: const _SplashScreen(),
    );
  }
}

/// Brand mark — Phase 5's Wisp logo, dropped in at
/// `assets/images/logo.png` and registered in pubspec.yaml's
/// `flutter.assets` list, next to the existing `.env` entry.
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.backgroundBase,
      body: Center(
        child: Image(
          image: AssetImage('assets/images/logo.png'),
          width: 160,
        ),
      ),
    );
  }
}

/// Shown only when `_WispBootstrapState._initialize()` genuinely throws
/// (bad/missing `.env`, unreachable Supabase project, etc.) — replaces
/// what used to be a silent fall-through into a broken `WispApp()`.
/// Deliberately a standalone `MaterialApp` for the same reason
/// `_SplashApp` is: nothing here can depend on `routerProvider`.
class _InitErrorApp extends StatelessWidget {
  const _InitErrorApp({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: Scaffold(
        backgroundColor: AppColors.backgroundBase,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    color: AppColors.error, size: 40),
                const SizedBox(height: 16),
                Text(
                  'Wisp couldn\'t start',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '$error',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class WispApp extends ConsumerWidget {
  const WispApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Wisp',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: router,
      builder: (context, child) =>
          _PresenceLifecycle(child: child ?? const SizedBox.shrink()),
    );
  }
}

/// Phase 4: drives app-wide online/offline presence off of two signals —
/// (1) the auth session appearing/disappearing (sign-in/sign-out), and
/// (2) the app moving to/from the foreground. Lives here rather than in
/// a screen because it must run for the entire app lifetime, not just
/// while a particular screen is mounted.
class _PresenceLifecycle extends ConsumerStatefulWidget {
  const _PresenceLifecycle({required this.child});
  final Widget child;

  @override
  ConsumerState<_PresenceLifecycle> createState() => _PresenceLifecycleState();
}

class _PresenceLifecycleState extends ConsumerState<_PresenceLifecycle>
    with WidgetsBindingObserver {
  bool _wasAuthenticated = false;

  // WISP_STABILITY_AND_STORY_VIEWERS_HANDOFF.md Part A permanent fix:
  // `ref` becomes invalid at the point this widget's `dispose()` runs —
  // calling `ref.read()`/`ref.watch()` *inside* `dispose()` itself is a
  // documented Riverpod anti-pattern that either throws visibly ("Bad
  // state: Cannot use \"ref\" after the widget was disposed") or
  // silently no-ops depending on Flutter's element-unmount timing.
  // `presenceControllerProvider` is a plain (non-family, non-autoDispose)
  // `Provider`, so the same `PresenceController` instance is returned
  // every time it's read — caching it once in a field, while `ref` is
  // still valid, and calling methods on that cached plain Dart object
  // inside `dispose()` is the correct, `ref`-free fix.
  PresenceController? _presenceController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _presenceController = ref.read(presenceControllerProvider);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presenceController?.goOffline();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (ref.read(currentSessionProvider) == null) return;
    switch (state) {
      case AppLifecycleState.resumed:
        // Force the access token fresh before anything realtime-related
        // (presence, message/call streams) tries to reconnect — see
        // AuthRepository.refreshSessionIfNeeded for why this has to run
        // first, not just rely on the SDK's background auto-refresh timer.
        ref.read(authRepositoryProvider).refreshSessionIfNeeded().then((_) {
          ref.read(presenceControllerProvider).goOnline();
        });
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        ref.read(presenceControllerProvider).goOffline();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAuthenticated = ref.watch(currentSessionProvider) != null;

    // Phase 10 — CallController flips to incomingRinging the moment a
    // 'ringing' row shows up for this user (see
    // incomingRingingCallProvider). That happens purely off a realtime
    // stream, with no screen necessarily watching for it, so this
    // app-wide listener is what actually surfaces the incoming-call
    // screen. `routerProvider`'s GoRouter is pushed directly (not via
    // `context.push`) since this widget sits above the Router in the
    // tree built by MaterialApp.router's `builder`.
    ref.listen<CallSessionState>(callControllerProvider, (previous, next) {
      final wasIncoming = previous?.phase == CallPhase.incomingRinging;
      if (!wasIncoming && next.phase == CallPhase.incomingRinging) {
        ref.read(routerProvider).push('/call');
      }
    });

    if (isAuthenticated != _wasAuthenticated) {
      _wasAuthenticated = isAuthenticated;
      // Defer past this build — presenceControllerProvider reads other
      // providers, which Riverpod doesn't allow mid-build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final controller = ref.read(presenceControllerProvider);
        isAuthenticated ? controller.goOnline() : controller.goOffline();
      });
    }

    return widget.child;
  }
}
