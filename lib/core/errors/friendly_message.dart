import 'package:supabase_flutter/supabase_flutter.dart';

import 'failure.dart';

/// Phase 11 polish pass: several screens were rendering `'$e'` directly
/// in the UI. Because repositories already wrap Supabase errors as
/// `SupabaseFailure(e.message)` / `AuthFailure(e.message)` (see
/// failure.dart), that `message` was itself just the raw Postgrest/
/// GoTrue error string (e.g. "permission denied for table
/// conversation_members", "JWT expired") — technically not a raw
/// exception reaching the UI (architecture.md's rule is nominally
/// satisfied), but not user-facing copy either. This maps the common,
/// recognizable cases to short human copy and falls back to one
/// generic, friendly message for anything unrecognized, rather than
/// ever dumping a database/auth error string in front of a user.
///
/// Deliberately conservative: this does NOT try to enumerate every
/// possible Postgrest/Auth error — just the handful actually seen in
/// this app's error paths (network/timeout, permission/RLS denial,
/// not-found, auth-session issues) plus a safe fallback. Extend this
/// list rather than reverting to raw text if a new recognizable case
/// shows up.
String friendlyErrorMessage(Object error) {
  final raw = switch (error) {
    Failure f => f.message,
    PostgrestException e => e.message,
    AuthException e => e.message,
    _ => error.toString(),
  };
  final lower = raw.toLowerCase();

  if (lower.contains('permission denied') ||
      lower.contains('row-level security') ||
      lower.contains('row level security')) {
    return "You don't have permission to view this right now.";
  }
  if (lower.contains('timed out') ||
      lower.contains('timeout') ||
      lower.contains('socketexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('network')) {
    return 'Connection problem. Check your internet and try again.';
  }
  if (lower.contains('jwt') ||
      lower.contains('session') ||
      lower.contains('not authenticated') ||
      lower.contains('signed in')) {
    return 'Your session needs refreshing. Try again in a moment.';
  }
  if (lower.contains('not found') || lower.contains('no rows')) {
    return "That couldn't be found. It may have been removed.";
  }

  return 'Something went wrong. Please try again.';
}
