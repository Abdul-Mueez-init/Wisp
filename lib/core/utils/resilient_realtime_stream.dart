// lib/core/utils/resilient_realtime_stream.dart
import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Wraps a Supabase Realtime-backed `.stream()` query so it
/// automatically resubscribes whenever the access token is refreshed.
///
/// Root cause this fixes (wisp_fixes.txt: "why tf the JWT tokens
/// expired, cause sometime the calls tab show this JWT tokens expired
/// issue"): a plain `client.from(table).stream()` opens one Realtime
/// channel that authenticates once, at subscribe time, with whatever
/// access token is current then. If the app is backgrounded long
/// enough for that token to actually expire (default Supabase access
/// token lifetime: 1 hour) — `SupabaseAuth` deliberately calls
/// `stopAutoRefresh()` while paused, so no refresh happens in the
/// background — the channel comes back from resume still holding the
/// now-expired token. The server rejects it with an
/// `InvalidJWTToken: Token has expired` error, and a plain
/// `StreamProvider` just sits in that error state: refreshing the
/// session afterward (see `AuthRepository.refreshSessionIfNeeded`,
/// called from the app-resume hook in `main.dart`) updates
/// `client.auth.currentSession`, and the Supabase SDK's own
/// `SupabaseClient._listenForAuthEvents` does call
/// `realtime.setAuth(newToken)` on a `tokenRefreshed` event — but that
/// does not by itself make an *already-errored/closed* channel rejoin.
/// The old channel just stays dead until something re-subscribes it,
/// which is what produced the "shows JWT expired, then eventually
/// works" flash the Calls tab exhibited.
///
/// This helper closes that gap generically, for any `.stream()`-based
/// repository method: it listens to `client.auth.onAuthStateChange`
/// itself and tears down + recreates the underlying subscription on
/// every `tokenRefreshed` (and `signedIn`, for the sign-out/sign-in-as-
/// someone-else case) event, so the caller never has to know this
/// happened — the returned broadcast stream just keeps emitting
/// correctly, indefinitely, across any number of background/expiry
/// cycles.
Stream<T> resilientRealtimeStream<T>(
  SupabaseClient client,
  Stream<T> Function() buildStream,
) {
  late final StreamController<T> controller;
  StreamSubscription<T>? innerSub;
  StreamSubscription<AuthState>? authSub;

  void resubscribe() {
    innerSub?.cancel();
    innerSub = buildStream().listen(
      (data) {
        if (!controller.isClosed) controller.add(data);
      },
      onError: (Object e, StackTrace st) {
        if (!controller.isClosed) controller.addError(e, st);
      },
    );
  }

  controller = StreamController<T>.broadcast(
    onListen: () {
      resubscribe();
      authSub = client.auth.onAuthStateChange.listen((state) {
        if (state.event == AuthChangeEvent.tokenRefreshed ||
            state.event == AuthChangeEvent.signedIn) {
          resubscribe();
        }
      });
    },
    onCancel: () {
      innerSub?.cancel();
      authSub?.cancel();
    },
  );

  return controller.stream;
}
