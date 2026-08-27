// lib/core/constants/language_options.dart

/// Shared preferred-language list. Used by onboarding (Phase 1) and
/// now the Settings screen (this gap-fix batch) so the two pickers can
/// never drift apart — previously this list only existed as a private
/// const inside onboarding_details_step.dart.
/// Not specified beyond ERD.md's `preferred_language default 'en'` —
/// a reasonable starter list for AI Feature 1 (Phase 7) translation
/// targets, easy to extend later.
const languageOptions = <(String code, String label)>[
  ('en', 'English'),
  ('es', 'Spanish'),
  ('fr', 'French'),
  ('de', 'German'),
  ('pt', 'Portuguese'),
  ('ar', 'Arabic'),
  ('hi', 'Hindi'),
  ('ur', 'Urdu'),
  ('zh', 'Chinese'),
  ('ja', 'Japanese'),
];
