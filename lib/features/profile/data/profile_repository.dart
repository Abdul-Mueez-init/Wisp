import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/failure.dart';
import '../../../models/profile.dart';

/// All `profiles` table + avatar storage access goes through here
/// (rules.md Rule 8's "shared client wrapper" pattern, applied to the
/// profile domain — no feature code queries `profiles` directly).
class ProfileRepository {
  ProfileRepository(this._client);
  final SupabaseClient _client;

  static const _avatarBucket = 'avatars';

  Future<bool> isUsernameAvailable(String username) async {
    try {
      final result = await _client
          .from('profiles')
          .select('id')
          .eq('username', username)
          .maybeSingle();
      return result == null;
    } on PostgrestException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  Future<Profile?> fetchProfile(String userId) async {
    try {
      final row = await _client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();
      if (row == null) return null;
      return Profile.fromJson(row);
    } on PostgrestException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  Future<Profile> createProfile({
    required String id,
    required String username,
    String? displayName,
    String? avatarPath,
    required String preferredLanguage,
  }) async {
    try {
      final row = await _client
          .from('profiles')
          .insert({
            'id': id,
            'username': username,
            'display_name': displayName,
            'avatar_url': avatarPath,
            'preferred_language': preferredLanguage,
          })
          .select()
          .single();
      return Profile.fromJson(row);
    } on PostgrestException catch (e) {
      // Most likely the unique(username) constraint — surface clearly.
      if (e.code == '23505') {
        throw const SupabaseFailure(
            'That username was just taken. Try another.');
      }
      throw SupabaseFailure(e.message);
    }
  }

  /// Uploads avatar bytes and returns the storage PATH (per ERD.md:
  /// "avatar_url ... Supabase Storage path"), not a resolved URL.
  /// Callers resolve a displayable URL via [resolveAvatarUrl].
  Future<String> uploadAvatar({
    required String userId,
    required Uint8List bytes,
    required String fileExt,
  }) async {
    try {
      final path = '$userId/avatar.$fileExt';
      await _client.storage.from(_avatarBucket).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );
      return path;
    } on StorageException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  /// Resolves a stored avatar path into a public URL for display.
  /// Assumes the `avatars` Storage bucket is public.
  String resolveAvatarUrl(String avatarPath) {
    return _client.storage.from(_avatarBucket).getPublicUrl(avatarPath);
  }
}
