// lib/features/calls/providers/call_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/supabase_config.dart';
import '../../../models/call.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/call_repository.dart';

final callRepositoryProvider = Provider<CallRepository>((ref) {
  return CallRepository(SupabaseConfig.client);
});

/// Realtime stream of every call row this user can see under RLS
/// (per architecture.md, "Realtime data → StreamProvider"). Powers
/// both the global incoming-call detector (see CallController) and
/// the Calls tab's history list (Batch 10c).
final myVisibleCallsStreamProvider = StreamProvider<List<Call>>((ref) {
  return ref.watch(callRepositoryProvider).watchMyVisibleCalls();
});

/// A single conversation's call rows — used by ChatDetailScreen to
/// show an "ongoing call" banner for the chat it's currently open on.
final callsForConversationProvider =
    StreamProvider.family<List<Call>, String>((ref, conversationId) {
  return ref
      .read(callRepositoryProvider)
      .watchCallsForConversation(conversationId);
});

/// Derives "is there a call ringing for me right now, that I didn't
/// place myself" straight off [myVisibleCallsStreamProvider] — kept as
/// its own provider so CallController's incoming-call listener has a
/// single clean value to watch rather than re-filtering the raw list
/// itself.
final incomingRingingCallProvider = Provider<Call?>((ref) {
  final myId = ref.watch(currentSessionProvider)?.user.id;
  if (myId == null) return null;
  final calls = ref.watch(myVisibleCallsStreamProvider).value ?? const [];
  for (final call in calls) {
    if (call.status == 'ringing' && call.callerId != myId) {
      return call;
    }
  }
  return null;
});
