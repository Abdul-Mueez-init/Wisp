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
  /// row already in [state]'s list — with one code path: replace by id
  /// if present, otherwise insert in sorted position. Sorted-insert
  /// (rather than always "append at the end") matters because a live
  /// insert event can in principle race a `loadOlder()` page that
  /// hasn't resolved yet; landing in the right spot doesn't depend on
  /// assuming arrival order.
  void _upsert(Message message) {
    final list = [...state.messages];
    final index = list.indexWhere((m) => m.id == message.id);
    if (index != -1) {
      list[index] = message;
    } else {
      list.insert(_sortedInsertIndex(list, message), message);
    }
    state = state.copyWith(messages: list);
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

final messageStatusesStreamProvider =
    StreamProvider<List<MessageStatus>>((ref) {
  return ref.watch(messageRepositoryProvider).watchMyVisibleStatuses();
});

/// Perf fix (WISP_PERFORMANCE_HANDOFF.md §5) — indexes the raw status
/// list by `messageId` once per stream emission, instead of every
/// message bubble scanning the full list with `.where()` on every
/// build. `MessageBubble`'s status-tick widget watches this via
/// `.select` so a status change only rebuilds the one bubble it
/// belongs to, not the whole message list or screen. Same values,
/// same semantics as before — just an O(1) lookup instead of O(n).
final messageStatusByIdProvider = Provider<Map<String, MessageStatus>>((ref) {
  final statuses = ref.watch(messageStatusesStreamProvider).value ?? const [];
  return {for (final s in statuses) s.messageId: s};
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
final mediaSignedUrlProvider =
    FutureProvider.family<String, String>((ref, mediaPath) {
  return ref.watch(mediaRepositoryProvider).resolveSignedUrl(mediaPath);
});

/// Batch 5b — URL + filename + size. Used by document bubbles.
final mediaFileInfoProvider =
    FutureProvider.family<MediaFileInfo, String>((ref, mediaPath) {
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

      // Find the row we just inserted so we know which id to update.
      // sendTextMessage doesn't return the new row's id today, so we
      // look it up by (conversation, sender, content, most recent) —
      // a small extra read, same "acceptable at demo scale" reasoning
      // already used elsewhere (e.g. MediaRepository's extra list()
      // call, per context.md).
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
    // Phase 2 (wisp_fixes_handoff.md item 1) — re-encode to WebP before
    // the upload-cap check below, so [MediaRepository.maxImageBytes]
    // applies to what actually reaches Storage. Falls back to the
    // original bytes on any compression failure (see
    // MediaRepository.reencodeImageToWebp's doc comment), so this
    // never blocks a send.
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

    // Phase 9 — fire-and-forget, same "don't hold up the send" shape
    // as Phase 7's translation step (see SendMessageController). The
    // voice note itself has already landed and is playable; a failed
    // transcription/action-extraction pass is never surfaced as a
    // failed *send*.
    if (!result.hasError && type == 'voice') {
      unawaited(_transcribeAndExtractActions(
        messageId: messageId,
        audioBytes: bytes,
      ));
    }

    return !result.hasError;
  }

  /// AI Feature 3 (PRD.md §10, Phase 9): transcribes the voice note via
  /// Gemini's native audio input, then runs a second text pass over
  /// the transcript to pull out action items/reminders — both results
  /// written back onto the same `messages` row so the realtime stream
  /// (already open on this conversation, per `chatMessagesControllerProvider`)
  /// carries them to both sides the moment they're ready. Unlike
  /// translation, this isn't scoped to direct chats —
  /// `voice_transcript`/`voice_actions` are per-message columns, not
  /// per-recipient, so there's no group-chat ambiguity to work around.
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
      } catch (_) {
        // The transcript is still worth saving even if the second
        // (action-extraction) pass fails — two independent AI calls
        // per plan.md, not an all-or-nothing pair.
      }

      await ref.read(messageRepositoryProvider).updateVoiceTranscription(
            messageId: messageId,
            transcript: transcript,
            actions: actions.isEmpty
                ? null
                : {'items': actions.map((a) => a.toJson()).toList()},
          );
    } catch (_) {
      // Best-effort — see the doc comment above.
    }
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
