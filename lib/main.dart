import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/ai_config.dart';
import 'config/supabase_config.dart';
import 'core/routes/app_router.dart';
import 'core/theme/app_theme.dart';

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
    );
  }
}
