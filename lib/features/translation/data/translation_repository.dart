// lib/features/translation/data/translation_repository.dart
import 'dart:convert';

import '../../../config/ai_config.dart';
import '../../../core/errors/failure.dart';

/// Result of a combined detect+translate call. [translatedText] is
/// null when [detectedLanguage] already matches the target the caller
/// asked for — per PRD.md §10, nothing is shown as "translated" when
/// the sender already wrote in the receiver's language (including the
/// English-source case).
class TranslationResult {
  const TranslationResult({
    required this.detectedLanguage,
    required this.translatedText,
  });

  final String detectedLanguage; // ISO 639-1, e.g. 'en', 'es'
  final String? translatedText;
}

/// All translation-specific AI calls go through here — the call itself
/// still routes through `AiConfig` per rules.md Rule 8; this repository
/// just owns the prompt shape and response parsing, same split as
/// every other feature's `data/` layer.
class TranslationRepository {
  const TranslationRepository();

  /// One combined call: detect the source language of [text], and
  /// translate it to [targetLanguageCode] if it isn't already in
  /// that language. Single JSON-only response so this is one Gemini/
  /// Groq round trip instead of two.
  Future<TranslationResult> detectAndTranslate({
    required String text,
    required String targetLanguageCode,
  }) async {
    final systemInstruction =
        'You are a language detection and translation engine embedded '
        'in a chat app. You will be given a single chat message. Detect '
        'its language as an ISO 639-1 code. If that code matches the target '
        'language code "$targetLanguageCode", set "translation" to null '
        '(no translation needed). Otherwise, translate the message '
        'into the language with ISO 639-1 code "$targetLanguageCode", '
        'preserving tone and any emoji, and put the result in '
        '"translation". '
        'Respond with ONLY raw JSON, no markdown fences, no commentary, '
        'in exactly this shape: '
        '{"language":"<ISO 639-1 code>","translation":"<string or null>"}';

    final raw = await AiConfig.generateText(
      prompt: text,
      systemInstruction: systemInstruction,
    );

    try {
      final match = RegExp(r'\{[\s\S]*\}').firstMatch(raw);
      if (match == null) {
        throw const AiFailure('No JSON found in translation response.');
      }
      final decoded = jsonDecode(match.group(0)!) as Map<String, dynamic>;
      final language = decoded['language'] as String?;
      final translation = decoded['translation'] as String?;
      if (language == null) {
        throw const AiFailure('Translation response missing "language".');
      }

      final isSameLanguage =
          language.toLowerCase() == targetLanguageCode.toLowerCase();
      final hasValidTranslation =
          translation != null && translation.trim().isNotEmpty;

      return TranslationResult(
        detectedLanguage: language,
        translatedText: (isSameLanguage || !hasValidTranslation)
            ? null
            : translation.trim(),
      );
    } catch (e) {
      throw AiFailure('Could not parse translation response: $e');
    }
  }
}
