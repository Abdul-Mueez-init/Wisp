// lib/features/chat/providers/message_provider.dart
import 'dart:typed_data';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../config/supabase_config.dart';
import '../../../core/errors/failure.dart';
import '../../../models/message.dart';
import '../../../models/message_status.dart';
import '../../../models/profile.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/media_repository.dart';
import '../data/message_event.dart';
import '../data/message_repository.dart';
import '../providers/conversation_provider.dart';
import '../../translation/providers/translation_provider.dart';
import '../../ai_agent/providers/ai_agent_provider.dart';
import '../../voice_notes/data/voice_transcription_repository.dart';
import '../../voice_notes/providers/voice_transcription_provider.dart';

final messageRepositoryProvider = Provider<MessageRepository>((ref) {
  return MessageRepository(SupabaseConfig.client);
});

final mediaRepositoryProvider = Provider<MediaRepository>((ref) {
  return MediaRepository(SupabaseConfig.client);
});

/// Phase D (WISP_PERFORMANCE_HANDOFF.md §11) state for one
/// conversation's message window: a bounded, paginated slice of
/// history (always oldest-first, same ordering the old
/// `messagesStreamProvider` guaranteed) plus whatever has arrived live
/// since the initial page was fetched.
class ChatMessagesState {
  const ChatMessagesState({
    this.messages = const [],
    this.isLoadingInitial = true,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
  });

  final List<Message> messages;
  final bool isLoadingInitial;
  final bool isLoadingMore;
  final bool hasMore;
  final Object? error;

  ChatMessagesState copyWith({
    List<Message>? messages,
    bool? isLoadingInitial,
    bool? isLoadingMore,
    bool? hasMore,
    Object? error,
    bool clearError = false,
  }) {
    return ChatMessagesState(
      messages: messages ?? this.messages,
      isLoadingInitial: isLoadingInitial ?? this.isLoadingInitial,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Phase D — owns one conversation's paginated message window: an
/// initial page fetched once via `MessageRepository.fetchRecentMessages`,
/// older pages fetched on demand as the user scrolls up
/// (`fetchOlderMessages`), and a conversation-scoped Realtime channel
/// (`watchConversationEvents`) merging live insert/update/delete events
/// into that same bounded list. Replaces `messagesStreamProvider`'s old
/// full-conversation `.stream()`, which re-sent and re-mapped *every*
/// message in the conversation on every single change.
class ChatMessagesController extends StateNotifier<ChatMessagesState> {
  ChatMessagesController(this._repo, this._conversationId)
      : super(const ChatMessagesState()) {
    _init();
  }

  static const _pageSize = 30;

  final MessageRepository _repo;
  final String _conversationId;
  RealtimeChannel? _channel;

  Future<void> _init() async {
    try {
      final initial = await _repo.fetchRecentMessages(
        conversationId: _conversationId,
        limit: _pageSize,
      );
      if (mounted) {
        state = state.copyWith(
          messages: initial,
          isLoadingInitial: false,
          hasMore: initial.length >= _pageSize,
        );
      }
    } catch (e) {
      if (mounted) {
        state = state.copyWith(isLoadingInitial: false, error: e);
      }
    }
    // Subscribed regardless of whether the initial fetch succeeded — a
    // transient fetch failure shouldn't also cost the live stream, and
    // the widget can still recover once a first live event arrives.
    if (mounted) {
      _channel = _repo.watchConversationEvents(
        conversationId: _conversationId,
        onEvent: _applyEvent,
      );
    }
  }

  /// Older page fetched on demand and prepended. Prepending to the
  /// *start* of this ascending list means it lands at the *end* of
  /// `ChatDetailScreen`'s `reverse: true` `ListView` (its reversed
  /// copy) — off-screen above whatever the user is currently looking
  /// at, so this never disturbs their scroll position the way
  /// inserting at the visible/newest end would.
  Future<void> loadOlder() async {
    if (state.isLoadingMore || !state.hasMore || state.messages.isEmpty) {
      return;
    }
    state = state.copyWith(isLoadingMore: true);
    try {
      final oldestLoaded = state.messages.first.createdAt;
      final older = await _repo.fetchOlderMessages(
        conversationId: _conversationId,
        before: oldestLoaded,
        limit: _pageSize,
      );
      if (!mounted) return;
      state = state.copyWith(
        messages: [...older, ...state.messages],
        isLoadingMore: false,
        hasMore: older.length >= _pageSize,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoadingMore: false, error: e);
    }
  }

  void _applyEvent(MessageEvent event) {
    if (!mounted) return;
    switch (event.type) {
      case MessageEventType.insert:
      case MessageEventType.update:
        _upsert(event.message!);
        break;
      case MessageEventType.delete:
        state = state.copyWith(
          messages: state.messages.where((m) => m.id != event.id).toList(),
        );
        break;
    }
  }

  /// Handles both a brand-new message (insert) and an existing row
  /// changing in place — Phase 7 translation, Phase 9 voice
  /// transcription/actions, live-location pin updates: all UPDATEs on a
  /// row already in [state]'s list.
  ///
  /// Optimization: if an existing message row is unchanged, no-ops to avoid
  /// triggering unneeded state notifications.
  ///
  /// BUGFIX: this previously compared `current[index] == message`, but
  /// `Message` (models/message.dart) doesn't override `operator ==` or
  /// `hashCode` — it falls back to `Object`'s identity comparison. Every
  /// `Message` here comes from `Message.fromJson`, a fresh object every
  /// single time, so that comparison was `false` for every single
  /// realtime UPDATE, including genuine no-op re-deliveries of an
  /// unchanged row. The "skip no-op upsert" optimization never actually
  /// skipped anything — dead code, not a working optimization. Replaced
  /// with an explicit field-by-field comparison of the columns that can
  /// actually change post-insert (translation, voice transcript/actions,
  /// live-location pin/expiry), so a genuine no-op update now correctly
  /// short-circuits without a `List.from` copy or a `state` reassignment.
  /// Deliberately done here rather than adding `==`/`hashCode` to the
  /// shared `Message` model, since that model is used elsewhere in the
  /// app (equality there could have wider, unrelated effects) — this
  /// keeps the fix contained to the one place it's actually needed.
  void _upsert(Message message) {
    final current = state.messages;
    final index = current.indexWhere((m) => m.id == message.id);
    if (index != -1) {
      if (_unchanged(current[index], message)) return;
      final list = List<Message>.from(current);
      list[index] = message;
      state = state.copyWith(messages: list);
    } else {
      final list = List<Message>.from(current);
      list.insert(_sortedInsertIndex(list, message), message);
      state = state.copyWith(messages: list);
    }
  }

  /// True if [a] and [b] are the same message row with no field changed
  /// that this app ever actually mutates post-insert. `id`/`conversationId`
  /// /`senderId`/`type`/`createdAt` are immutable once a row exists, so
  /// they're intentionally not part of this check.
  bool _unchanged(Message a, Message b) {
    return a.content == b.content &&
        a.mediaUrl == b.mediaUrl &&
        a.originalLanguage == b.originalLanguage &&
        a.translatedContent == b.translatedContent &&
        a.sharedContactId == b.sharedContactId &&
        a.locationLat == b.locationLat &&
        a.locationLng == b.locationLng &&
        a.isLiveLocation == b.isLiveLocation &&
        a.liveLocationExpiresAt == b.liveLocationExpiresAt &&
        a.voiceTranscript == b.voiceTranscript &&
        _voiceActionsEqual(a.voiceActions, b.voiceActions);
  }

  /// `voiceActions` is a `Map<String, dynamic>?` (decoded jsonb) — two
  /// separately-decoded maps with identical content are also not `==`
  /// under Dart's default map equality, so this compares key/value pairs
  /// directly instead of relying on `==`. Shallow is sufficient here: the
  /// only writer of this field (`updateVoiceTranscription`) always
  /// replaces it wholesale rather than mutating nested values.
  bool _voiceActionsEqual(Map<String, dynamic>? a, Map<String, dynamic>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  int _sortedInsertIndex(List<Message> list, Message message) {
    var low = 0;
    var high = list.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (list[mid].createdAt.isBefore(message.createdAt)) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) {
      SupabaseConfig.client.removeChannel(channel);
    }
    super.dispose();
  }
}

/// Phase D — one controller/channel per open conversation, `autoDispose`d
/// (closing its Realtime channel with it, via
/// `ChatMessagesController.dispose`) the moment `ChatDetailScreen`
/// unmounts, so leaving a chat doesn't leave a subscription running in
/// the background indefinitely.
final chatMessagesControllerProvider = StateNotifierProvider.autoDispose
    .family<ChatMessagesController, ChatMessagesState, String>(
        (ref, conversationId) {
  return ChatMessagesController(
    ref.watch(messageRepositoryProvider),
    conversationId,
  );
});

/// Phase 4 optimization: auto-disposed when no widget is watching status ticks,
/// preventing idle background status stream subscriptions.
///
/// NOT narrowed to one conversation: `message_status` has no
/// `conversation_id` column, and Supabase Realtime's `PostgresChangeFilter`
/// only supports a single-column `eq` — there is no server-side way to
/// filter this table's changefeed down to "just the rows for messages in
/// conversation X" without denormalizing a `conversation_id` column onto
/// `message_status` (or adding a dedicated RPC/view). That is a schema
/// change and, per rules.md Rule 8, is NOT made silently here — it needs
/// to be raised with the user and confirmed as its own migration before
/// implementation. Until then, this stream is necessarily RLS-scoped to
/// "everything this user is allowed to see" rather than one conversation.
final messageStatusesStreamProvider =
    StreamProvider.autoDispose<List<MessageStatus>>((ref) {
  return ref.watch(messageRepositoryProvider).watchMyVisibleStatuses();
});

/// Phase 4 narrowing (client-side, given the schema constraint above) —
/// scoped per open conversation via `.family` instead of one shared global
/// map. Derives the subset of [messageStatusesStreamProvider]'s rows that
/// belong to messages actually loaded in [conversationId]'s current
/// window (the same bounded list `chatMessagesControllerProvider` already
/// maintains), so:
///  - a status event for a message in some *other*, currently-closed
///    conversation never appears in the map this screen's bubbles depend
///    on, and doesn't grow it;
///  - the map itself stays bounded to this conversation's loaded window
///    (tens of messages), not this user's entire status history;
///  - it's `.autoDispose` and `.family`-scoped, so it's torn down the
///    moment `ChatDetailScreen` for that conversation unmounts, same
///    lifecycle as `chatMessagesControllerProvider`.
/// `MessageBubble`'s status-tick widget still watches this via `.select`
/// so a status change only rebuilds the one bubble it belongs to, not the
/// whole message list or screen. Same values, same semantics as before —
/// just bounded to what this conversation actually needs instead of every
/// status row this user can see across every conversation.
final messageStatusByIdProvider = Provider.autoDispose
    .family<Map<String, MessageStatus>, String>((ref, conversationId) {
  final relevantIds = ref
      .watch(chatMessagesControllerProvider(conversationId))
      .messages
      .map((m) => m.id)
      .toSet();
  if (relevantIds.isEmpty) return const {};
  final statuses = ref.watch(messageStatusesStreamProvider).value ?? const [];
  return {
    for (final s in statuses)
      if (relevantIds.contains(s.messageId)) s.messageId: s,
  };
});

final otherDirectMemberProvider =
    FutureProvider.family<Profile?, String>((ref, conversationId) async {
  final myId = ref.watch(currentSessionProvider)?.user.id;
  if (myId == null) return null;
  return ref.read(conversationRepositoryProvider).getOtherDirectMember(
        conversationId: conversationId,
        myId: myId,
      );
});

/// Lightweight — URL only. Used by image/video/voice bubbles.
///
/// Phase 6 fix: this was a plain (non-autoDispose) `FutureProvider.family`,
/// meaning the provider container kept one entry alive *forever* for
/// every distinct media path ever viewed in the current app session —
/// unbounded growth for a long-lived chat with lots of media, on top of
/// `MediaRepository`'s own in-memory cache. Made `.autoDispose`: when a
/// bubble scrolls far enough off-screen that `ListView.builder` disposes
/// its widget (and nothing else is watching this path), the provider
/// entry is torn down too. If the same media scrolls back into view,
/// `MediaRepository`'s own signed-URL/file-info cache (keyed the same way,
/// with its own bounded eviction — see media_repository.dart) still
/// serves it as an in-memory hit rather than a real network request, so
/// autoDispose here doesn't reintroduce duplicate Storage calls.
final mediaSignedUrlProvider =
    FutureProvider.autoDispose.family<String, String>((ref, mediaPath) {
  return ref.watch(mediaRepositoryProvider).resolveSignedUrl(mediaPath);
});

/// Batch 5b — URL + filename + size. Used by document bubbles.
/// Same Phase 6 `.autoDispose` fix and reasoning as [mediaSignedUrlProvider].
final mediaFileInfoProvider =
    FutureProvider.autoDispose.family<MediaFileInfo, String>((ref, mediaPath) {
  return ref.watch(mediaRepositoryProvider).resolveFileInfo(mediaPath);
});

class SendMessageController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> sendText({
    required String conversationId,
    required String content,
    // Phase 8 — true only for the reserved AI-DM conversation
    // (`findOrCreateAiConversation`), where every message gets an
    // agent reply rather than requiring an explicit "@wisp" mention.
    // Passed in by `ChatDetailScreen`, which already knows this from
    // routing, rather than re-derived here with an extra query.
    bool isAiConversation = false,
  }) async {
    final myId = ref.read(currentSessionProvider)?.user.id;
    if (myId == null || content.trim().isEmpty) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(messageRepositoryProvider).sendTextMessage(
            conversationId: conversationId,
            senderId: myId,
            content: content,
          ),
    );
    // Fire-and-forget: don't hold up the send (or its `state`) on a
    // Gemini/Groq round trip — PRD.md's "realtime... must feel
    // instant" principle. A failed translation/agent reply is
    // swallowed, never surfaced as a failed *send*, since the message
    // already landed.
    if (!state.hasError) {
      unawaited(_translateIfDirect(
        conversationId: conversationId,
        content: content,
      ));
      unawaited(ref.read(aiAgentControllerProvider.notifier).maybeRespond(
            conversationId: conversationId,
            triggerText: content,
            forceRespond: isAiConversation,
          ));
    }
  }

  /// Phase 7, scoped to direct chats only per the Phase 7 handoff doc's
  /// Decision #1 — `messages.translated_content` is a single column
  /// per row, which can't cleanly represent "translated differently
  /// per recipient" for a group. Group messages are left untranslated
  /// until/unless that becomes its own schema-backed phase.
  Future<void> _translateIfDirect({
    required String conversationId,
    required String content,
  }) async {
    final myId = ref.read(currentSessionProvider)?.user.id;
    if (myId == null) return;
    try {
      final conversation = await ref
          .read(conversationRepositoryProvider)
          .getConversation(conversationId);
      if (conversation == null || !conversation.isDirect) return;

      final otherMember = await ref
          .read(conversationRepositoryProvider)
          .getOtherDirectMember(conversationId: conversationId, myId: myId);
      if (otherMember == null) return;

      final justSent =
          await ref.read(messageRepositoryProvider).findMostRecentTextMessage(
                conversationId: conversationId,
                senderId: myId,
                content: content.trim(),
              );
      if (justSent == null) return;

      final result =
          await ref.read(translationRepositoryProvider).detectAndTranslate(
                text: content.trim(),
                targetLanguageCode: otherMember.preferredLanguage,
              );

      await ref.read(messageRepositoryProvider).updateTranslation(
            messageId: justSent,
            originalLanguage: result.detectedLanguage,
            translatedContent: result.translatedText,
          );
    } catch (_) {
      // Best-effort — see the doc comment above.
    }
  }

  /// Batch 5d — no upload involved (unlike image/video/document/voice),
  /// so this lives alongside [sendText] rather than in
  /// `SendMediaMessageController`. Returns `bool` (unlike [sendText])
  /// so `chat_detail_screen.dart` can reuse its existing media-style
  /// error-surfacing wrapper for the attachment-sheet flow it's
  /// triggered from.
  Future<bool> sendContact({
    required String conversationId,
    required String sharedContactId,
  }) async {
    final myId = ref.read(currentSessionProvider)?.user.id;
    if (myId == null) return false;
    state = const AsyncLoading();
    final result = await AsyncValue.guard(
      () => ref.read(messageRepositoryProvider).sendContactMessage(
            conversationId: conversationId,
            senderId: myId,
            sharedContactId: sharedContactId,
          ),
    );
    state = result;
    return !result.hasError;
  }
}

final sendMessageControllerProvider =
    AsyncNotifierProvider<SendMessageController, void>(
  SendMessageController.new,
);

/// Phase 5 — send an image/video/document/voice message: upload bytes
/// to `chat-media`, then insert the `messages` row referencing the
/// resulting path. Every `send*` method returns `false` (leaving a
/// real error in `state`) rather than silently no-oping on failure.
/// The four public methods are thin wrappers around one shared
/// `_sendMedia` so the upload-cap-check → upload → insert flow isn't
/// duplicated per type.
class SendMediaMessageController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<bool> sendImage({
    required String conversationId,
    required Uint8List bytes,
    required String fileExt,
    String? caption,
  }) async {
    final webpBytes =
        await ref.read(mediaRepositoryProvider).reencodeImageToWebp(bytes);
    return _sendMedia(
      conversationId: conversationId,
      bytes: webpBytes,
      fileName: 'photo.webp',
      type: 'image',
      maxBytes: MediaRepository.maxImageBytes,
      maxBytesLabel: '8MB',
      caption: caption,
    );
  }

  Future<bool> sendVideo({
    required String conversationId,
    required Uint8List bytes,
    required String fileExt,
    String? caption,
  }) {
    return _sendMedia(
      conversationId: conversationId,
      bytes: bytes,
      fileName: 'video.$fileExt',
      type: 'video',
      maxBytes: MediaRepository.maxVideoBytes,
      maxBytesLabel: '50MB',
      caption: caption,
    );
  }

  Future<bool> sendDocument({
    required String conversationId,
    required Uint8List bytes,
    required String fileName,
    String? caption,
  }) {
    return _sendMedia(
      conversationId: conversationId,
      bytes: bytes,
      fileName: fileName,
      type: 'document',
      maxBytes: MediaRepository.maxDocumentBytes,
      maxBytesLabel: '25MB',
      caption: caption,
    );
  }

  Future<bool> sendVoice({
    required String conversationId,
    required Uint8List bytes,
  }) {
    return _sendMedia(
      conversationId: conversationId,
      bytes: bytes,
      fileName: 'voice.m4a',
      type: 'voice',
      maxBytes: MediaRepository.maxVoiceBytes,
      maxBytesLabel: '10MB',
    );
  }

  Future<bool> _sendMedia({
    required String conversationId,
    required Uint8List bytes,
    required String fileName,
    required String type,
    required int maxBytes,
    required String maxBytesLabel,
    String? caption,
  }) async {
    final myId = ref.read(currentSessionProvider)?.user.id;
    if (myId == null) return false;

    if (bytes.length > maxBytes) {
      state = AsyncError(
        ValidationFailure(
          '${_typeLabel(type)} is too large (max $maxBytesLabel).',
        ),
        StackTrace.current,
      );
      return false;
    }

    state = const AsyncLoading();
    final messageId = const Uuid().v4();
    final result = await AsyncValue.guard(() async {
      final path = await ref.read(mediaRepositoryProvider).uploadBytes(
            conversationId: conversationId,
            messageId: messageId,
            fileName: fileName,
            bytes: bytes,
          );
      await ref.read(messageRepositoryProvider).sendMediaMessage(
            messageId: messageId,
            conversationId: conversationId,
            senderId: myId,
            type: type,
            mediaPath: path,
            caption: caption,
          );
    });
    state = result;

    if (!result.hasError && type == 'voice') {
      unawaited(_transcribeAndExtractActions(
        messageId: messageId,
        audioBytes: bytes,
      ));
    }

    return !result.hasError;
  }

  Future<void> _transcribeAndExtractActions({
    required String messageId,
    required Uint8List audioBytes,
  }) async {
    try {
      final repo = ref.read(voiceTranscriptionRepositoryProvider);
      final transcript = await repo.transcribe(audioBytes);
      if (transcript.trim().isEmpty) return;

      List<VoiceActionItem> actions = const [];
      try {
        actions = await repo.extractActions(transcript);
      } catch (_) {}

      await ref.read(messageRepositoryProvider).updateVoiceTranscription(
            messageId: messageId,
            transcript: transcript,
            actions: actions.isEmpty
                ? null
                : {'items': actions.map((a) => a.toJson()).toList()},
          );
    } catch (_) {}
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'video':
        return 'Video';
      case 'document':
        return 'Document';
      case 'voice':
        return 'Voice note';
      default:
        return 'Image';
    }
  }
}

final sendMediaMessageControllerProvider =
    AsyncNotifierProvider<SendMediaMessageController, void>(
  SendMediaMessageController.new,
);
