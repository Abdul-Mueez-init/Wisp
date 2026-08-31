import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/failure.dart';
import '../../../models/profile.dart';

/// All username-search queries against `profiles` go through here
/// (rules.md Rule 8's shared-wrapper pattern, extended beyond AI/auth
/// to every domain that touches Supabase).
class ContactsRepository {
  ContactsRepository(this._client);
  final SupabaseClient _client;

  /// Searches `profiles.username` (case-insensitive, partial match) per
  /// PRD.md section 5: "Users search for others by username." Excludes
  /// [excludeUserId] (the current user) from results.
  Future<List<Profile>> searchByUsername(
    String query, {
    required String excludeUserId,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    try {
      final rows = await _client
          .from('profiles')
          .select()
          .ilike('username', '%$trimmed%')
          .neq('id', excludeUserId)
          .order('username', ascending: true)
          .limit(20);
      return (rows as List)
          .map((row) => Profile.fromJson(row as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }
}
