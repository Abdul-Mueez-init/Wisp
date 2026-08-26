import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/supabase_config.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/typing_repository.dart';

final typingRepositoryProvider = Provider<TypingRepository>((ref) {
  return TypingRepository(SupabaseConfig.client);
});

/// Other users currently typing in [conversationId] — excludes this
/// user and filters out stale rows (see TypingRepository.isFresh).
final typingUsersStreamProvider =
    StreamProvider.family<List<String>, String>((ref, conversationId) {
  final myId = ref.watch(currentSessionProvider)?.user.id;
  return ref
      .watch(typingRepositoryProvider)
      .watchTypingRows(conversationId)
      .map((rows) => rows
          .where((r) =>
              r['is_typing'] == true &&
              r['user_id'] != myId &&
              TypingRepository.isFresh(r))
          .map((r) => r['user_id'] as String)
          .toList());
});

/// Debounces this user's own typing state into `typing_status` upserts:
/// flips to typing on the first keystroke of a burst, and back to
/// not-typing after a few seconds of inactivity or on send/leave.
/// A one-off action per architecture.md, but stateful (the debounce
/// timer) so it's a plain [Notifier] rather than a fire-and-forget
/// function.
class TypingController extends Notifier<void> {
  Timer? _idleTimer;
  bool _isTyping = false;
  String? _activeConversationId;

  @override
  void build() {
    ref.onDispose(() {
      _idleTimer?.cancel();
      _clearIfTyping();
    });
  }

  void onTextChanged(String conversationId, String text) {
    _activeConversationId = conversationId;
    _idleTimer?.cancel();

    if (text.trim().isEmpty) {
      _clearIfTyping();
      return;
    }

    if (!_isTyping) {
      _isTyping = true;
      _write(conversationId, true);
    }
    _idleTimer = Timer(const Duration(seconds: 3), () {
      _clearIfTyping();
    });
  }

  /// Call when leaving the chat screen or right after sending a message.
  void stopTyping(String conversationId) {
    _activeConversationId = conversationId;
    _idleTimer?.cancel();
    _clearIfTyping();
  }

  void _clearIfTyping() {
    final conversationId = _activeConversationId;
    if (_isTyping && conversationId != null) {
      _isTyping = false;
      _write(conversationId, false);
    }
  }

  void _write(String conversationId, bool isTyping) {
    final myId = ref.read(currentSessionProvider)?.user.id;
    if (myId == null) return;
    // Fire-and-forget: a dropped typing-indicator update is invisible
    // and self-heals on the next keystroke, so it isn't surfaced as an
    // error to the user (same reasoning as PresenceController).
    ref
        .read(typingRepositoryProvider)
        .setTyping(
            conversationId: conversationId, userId: myId, isTyping: isTyping)
        .catchError((_) {});
  }
}

final typingControllerProvider = NotifierProvider<TypingController, void>(
  TypingController.new,
);
