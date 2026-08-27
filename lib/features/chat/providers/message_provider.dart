// lib/features/chat/providers/message_provider.dart
import 'dart:typed_data';

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
    return !result.hasError;
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
