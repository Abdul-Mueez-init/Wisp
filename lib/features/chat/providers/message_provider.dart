// lib/features/chat/providers/message_provider.dart
import 'dart:typed_data';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../config/supabase_config.dart';
import '../../../core/errors/failure.dart';
import '../../../models/message.dart';
import '../../../models/message_status.dart';
import '../../../models/profile.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/media_repository.dart';
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

final messagesStreamProvider =
    StreamProvider.family<List<Message>, String>((ref, conversationId) {
  return ref.watch(messageRepositoryProvider).watchMessages(conversationId);
});

final messageStatusesStreamProvider =
    StreamProvider<List<MessageStatus>>((ref) {
  return ref.watch(messageRepositoryProvider).watchMyVisibleStatuses();
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
  }) {
    return _sendMedia(
      conversationId: conversationId,
      bytes: bytes,
      fileName: 'photo.$fileExt',
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
  /// (already open on this conversation, per `messagesStreamProvider`)
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
