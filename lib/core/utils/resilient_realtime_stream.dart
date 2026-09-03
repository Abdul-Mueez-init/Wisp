// lib/core/utils/resilient_realtime_stream.dart
import 'dart:async';
import 'dart:math' as math;

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
///
/// WISP_STABILITY_AND_STORY_VIEWERS_HANDOFF.md Part B permanent fix:
/// the block above only ever solved the *expired-token* failure mode.
/// It did NOT handle the underlying Realtime channel's own subscribe
/// failures (`RealtimeSubscribeException(status: timedOut)`,
/// `channelError`, etc.) — a transient failure distinct from an
/// expired JWT that happens on flaky networks, a cold app start racing
/// the socket handshake, or a brief Realtime-server hiccup. Before this
/// fix, `onError` only forwarded the error to `controller` and gave up;
/// the stream sat in a permanent error state until an *unrelated*
/// `tokenRefreshed`/`signedIn` auth event happened to fire and
/// incidentally called `resubscribe()` again. That's the root cause of
/// "sometimes it recovers, sometimes it doesn't" — and for
/// `CallRepository.watchMyVisibleCalls()` specifically (the stream
/// `incomingRingingCallProvider` depends on), it's also the reason an
/// incoming call could silently never be detected at all: a cold app
/// start on the callee's device is exactly the scenario most likely to
/// race the socket handshake, and with no retry, that device's `calls`
/// stream could stay dead for the rest of the session with zero visible
/// sign anything was wrong.
///
/// Fix: on `onError`, schedule a `resubscribe()` retry on its own timer
/// using capped exponential backoff with jitter, instead of relying on
/// an unrelated auth event to ever happen to trigger recovery. The
/// error is still forwarded to `controller` on each failed attempt (so
/// a `StreamProvider`-driven UI can still show a real error state if
/// the person is genuinely offline), but the retry keeps happening in
/// the background regardless, so the stream self-heals the moment
/// connectivity actually returns — no manual refresh, no reliance on
/// the token happening to refresh.
Stream<T> resilientRealtimeStream<T>(
  SupabaseClient client,
  Stream<T> Function() buildStream,
) {
  late final StreamController<T> controller;
  StreamSubscription<T>? innerSub;
  StreamSubscription<AuthState>? authSub;
  Timer? retryTimer;
  final random = math.Random();

  const initialBackoff = Duration(seconds: 1);
  const maxBackoff = Duration(seconds: 20);
  var backoff = initialBackoff;

  Duration _withJitter(Duration d) {
    // +/- 20% jitter so many devices retrying at once (e.g. right after
    // a shared network hiccup) don't all hammer Realtime in lockstep.
    final jitterMs = (d.inMilliseconds * 0.2).round();
    final offset = jitterMs == 0 ? 0 : random.nextInt(jitterMs * 2) - jitterMs;
    final ms = (d.inMilliseconds + offset).clamp(0, maxBackoff.inMilliseconds);
    return Duration(milliseconds: ms);
  }

  void resubscribe() {
    retryTimer?.cancel();
    retryTimer = null;
    innerSub?.cancel();
    innerSub = buildStream().listen(
      (data) {
        backoff = initialBackoff; // reset on any successful emission
        if (!controller.isClosed) controller.add(data);
      },
      onError: (Object e, StackTrace st) {
        if (!controller.isClosed) controller.addError(e, st);
        // Permanent fix (Part B): retry subscribe failures on their own
        // schedule instead of only forwarding the error and giving up.
        retryTimer?.cancel();
        final delay = _withJitter(backoff);
        retryTimer = Timer(delay, resubscribe);
        backoff = (backoff * 2) > maxBackoff ? maxBackoff : backoff * 2;
      },
    );
  }

  controller = StreamController<T>.broadcast(
    onListen: () {
      backoff = initialBackoff;
      resubscribe();
      authSub = client.auth.onAuthStateChange.listen((state) {
        if (state.event == AuthChangeEvent.tokenRefreshed ||
            state.event == AuthChangeEvent.signedIn) {
          backoff = initialBackoff;
          resubscribe();
        }
      });
    },
    onCancel: () {
      retryTimer?.cancel();
      innerSub?.cancel();
      authSub?.cancel();
    },
  );

  return controller.stream;
}
