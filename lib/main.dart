import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/ai_config.dart';
import 'config/supabase_config.dart';
import 'core/routes/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/chat/providers/presence_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  await SupabaseConfig.initialize(
    url: dotenv.env['SUPABASE_URL'] ?? '',
    anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
  );

  AiConfig.initialize(
    geminiApiKey: dotenv.env['GEMINI_API_KEY'] ?? '',
    groqApiKey: dotenv.env['GROQ_API_KEY'] ?? '',
  );

  runApp(const ProviderScope(child: WispApp()));
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ref.read(presenceControllerProvider).goOffline();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (ref.read(currentSessionProvider) == null) return;
    switch (state) {
      case AppLifecycleState.resumed:
        ref.read(presenceControllerProvider).goOnline();
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
