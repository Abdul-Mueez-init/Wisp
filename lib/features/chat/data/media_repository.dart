// lib/features/chat/data/media_repository.dart
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/failure.dart';

/// Handles all `chat-media` Storage bucket access (upload, signed URL
/// resolution, file metadata). Mirrors the `avatars` bucket pattern in
/// `ProfileRepository`, with one deliberate difference: `chat-media` is
/// PRIVATE (per architecture.md "Storage Buckets"), so callers always
/// get back a storage PATH from upload and must resolve a short-lived
/// signed URL to actually display/download the file — never
/// `getPublicUrl`.
class MediaRepository {
  MediaRepository(this._client);
  final SupabaseClient _client;

  static const bucket = 'chat-media';

  /// Client-side upload caps — see architecture.md "Storage Buckets".
  static const maxImageBytes = 8 * 1024 * 1024; // 8MB
  static const maxVideoBytes = 50 * 1024 * 1024; // 50MB
  static const maxDocumentBytes = 25 * 1024 * 1024; // 25MB
  /// Batch 5c — generous relative to actual size: a 64kbps mono AAC
  /// recording this size would run ~20+ minutes.
  static const maxVoiceBytes = 10 * 1024 * 1024; // 10MB

  /// Path convention per architecture.md:
  /// `{conversation_id}/{message_id}/{filename}`. [messageId] is
  /// generated client-side (uuid) *before* the message row is
  /// inserted, so the same id doubles as both the storage path segment
  /// and `messages.id`. [fileName] is sanitized but otherwise kept
  /// as-is — for documents this is what lets the recipient see the
  /// real original filename (ERD.md has no separate filename column,
  /// so the path itself is the only place it can live).
  Future<String> uploadBytes({
    required String conversationId,
    required String messageId,
    required String fileName,
    required Uint8List bytes,
    String? contentType,
  }) async {
    final safeName = _sanitizeFileName(fileName);
    final path = '$conversationId/$messageId/$safeName';
    try {
      await _client.storage.from(bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: contentType ?? _guessContentType(safeName),
            ),
          );
      return path;
    } on StorageException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  /// Signed URL only — use for images/video/voice where the UI doesn't
  /// need to show a filename or size.
  Future<String> resolveSignedUrl(
    String path, {
    int expiresInSeconds = 3600,
  }) async {
    try {
      return await _client.storage
          .from(bucket)
          .createSignedUrl(path, expiresInSeconds);
    } on StorageException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  /// Batch 5b — signed URL *and* the object's byte size, for document
  /// bubbles ("report.pdf · 2.4 MB"). One extra `list()` call versus
  /// [resolveSignedUrl] (a signed-URL response has no size field) —
  /// preferred over inventing a `messages.file_size` column not in
  /// ERD.md.
  Future<MediaFileInfo> resolveFileInfo(String path) async {
    try {
      final segments = path.split('/');
      final fileName = segments.removeLast();
      final folder = segments.join('/');
      final listing = await _client.storage.from(bucket).list(path: folder);
      final match = listing.where((f) => f.name == fileName);
      final sizeBytes =
          match.isNotEmpty ? match.first.metadata?['size'] as int? : null;
      final url =
          await _client.storage.from(bucket).createSignedUrl(path, 3600);
      return MediaFileInfo(
        url: url,
        fileName: fileName,
        sizeBytes: sizeBytes,
      );
    } on StorageException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  String _sanitizeFileName(String name) {
    final base = name.split('/').last.split('\\').last;
    final cleaned = base.replaceAll(RegExp(r'[^\w.\-]'), '_');
    return cleaned.isEmpty ? 'file' : cleaned;
  }

  /// Best-effort content type from extension, so a downloaded file
  /// opens correctly instead of as generic `application/octet-stream`.
  /// Not exhaustive — just what this app's pickers/recorder can
  /// produce. 'm4a'/'aac' added in Batch 5c for voice notes.
  String? _guessContentType(String fileName) {
    final ext =
        fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    const map = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'webp': 'image/webp',
      'mp4': 'video/mp4',
      'mov': 'video/quicktime',
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt': 'application/vnd.ms-powerpoint',
      'pptx':
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'txt': 'text/plain',
      'csv': 'text/csv',
      'm4a': 'audio/m4a',
      'aac': 'audio/aac',
    };
    return map[ext];
  }
}

class MediaFileInfo {
  const MediaFileInfo({
    required this.url,
    required this.fileName,
    this.sizeBytes,
  });

  final String url;
  final String fileName;
  final int? sizeBytes;
}