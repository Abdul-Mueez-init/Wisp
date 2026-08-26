import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/supabase_config.dart';
import '../../../models/profile.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/contacts_repository.dart';

final contactsRepositoryProvider = Provider<ContactsRepository>((ref) {
  return ContactsRepository(SupabaseConfig.client);
});

/// Debounced username-search state, exposed as an AsyncNotifier so the
/// search screen only ever watches one provider for loading/data/error
/// (architecture.md: no `setState` for anything touching shared state;
/// the text field's own focus/text is the only acceptable local state).
class UsernameSearchController extends AsyncNotifier<List<Profile>> {
  Timer? _debounce;

  @override
  FutureOr<List<Profile>> build() {
    ref.onDispose(() => _debounce?.cancel());
    return [];
  }

  void search(String query) {
    _debounce?.cancel();

    if (query.trim().isEmpty) {
      state = const AsyncData([]);
      return;
    }

    // Keep showing previous results while the new query is in flight,
    // rather than flashing an empty list on every keystroke.
    state = AsyncLoading<List<Profile>>().copyWithPrevious(state);

    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final myId = ref.read(currentSessionProvider)?.user.id;
      if (myId == null) return;
      state = await AsyncValue.guard(
        () => ref.read(contactsRepositoryProvider).searchByUsername(
              query,
              excludeUserId: myId,
            ),
      );
    });
  }
}

final usernameSearchControllerProvider =
    AsyncNotifierProvider<UsernameSearchController, List<Profile>>(
  UsernameSearchController.new,
);
