// lib/features/translation/providers/translation_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/translation_repository.dart';

final translationRepositoryProvider = Provider<TranslationRepository>((ref) {
  return const TranslationRepository();
});
