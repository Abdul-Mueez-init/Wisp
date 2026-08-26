import 'package:supabase_flutter/supabase_flutter.dart';

/// Single Supabase client instance for the whole app. Repositories read
/// `SupabaseConfig.client` rather than calling `Supabase.instance.client`
/// directly, so initialization stays in one place (mirrors the
/// `AiConfig` pattern in `ai_config.dart`, per rules.md Rule 8's intent
/// extended to the Supabase client itself).
///
/// NOTE: this file was missing (0 bytes) despite being referenced by
/// main.dart and the auth/profile providers — filled in to match the
/// calls already made against it. Not a scope change, just completing
/// what Phase 0 was already documented as having built.
class SupabaseConfig {
  SupabaseConfig._();

  static Future<void> initialize({
    required String url,
    required String anonKey,
  }) async {
    await Supabase.initialize(url: url, anonKey: anonKey);
  }

  static SupabaseClient get client => Supabase.instance.client;
}
