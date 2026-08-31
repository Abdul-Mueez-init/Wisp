import 'dart:typed_data';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/errors/failure.dart';

/// Shared AI client wrapper per architecture.md "AI Integration Pattern":
/// tries Gemini first, falls back to Groq on rate-limit/error.
/// Feature code (translation/, ai_agent/, voice_notes/) must call
/// AiConfig methods only — never instantiate Gemini/Groq SDKs directly
/// (rules.md Rule 8).
///
/// Bugfix (post-Phase-11, live-outage triage): both models this file
/// previously pointed at were dead — `gemini-1.5-flash` 404s on every
/// call (the entire Gemini 1.0/1.5 family has been fully shut down by
/// Google) and Groq deprecated `llama-3.1-8b-instant` June 17, 2026.
/// Every call site already wraps `AiConfig` calls in a silent catch
/// (so as not to block message send on a translation/agent/transcription
/// failure), which is exactly why this looked like "the AI features were
/// never built" instead of a loud error. Also dropped the
/// `google_generative_ai` package entirely — it's deprecated and archived
/// upstream in favor of `firebase_ai`, which needs a full Firebase project
/// wired up (too heavy a lift for a model-string fix). Google's own docs
/// confirm the plain REST `generateContent` endpoint "remains fully
/// supported" even after their newer Interactions API, so this file now
/// calls it directly with the `http` package already used for Groq below
/// — no new dependency, no Firebase setup, still zero-cost.
/// Current replacements (verified against Google's/Groq's live docs,
/// Aug 2026): `gemini-3.5-flash` (free-tier, multimodal — text, image,
/// video, audio, PDF in, text out) and Groq's `openai/gpt-oss-20b`
/// (Groq's own recommended migration target for the retired 3.1-8b-instant,
/// also free-tier, same OpenAI-compatible chat-completions shape so no
/// request-building changes were needed there).
class AiConfig {
  AiConfig._();

  static late final String _geminiApiKey;
  static late final String _groqApiKey;
  static bool _initialized = false;

  static const String _geminiModel = 'gemini-3.5-flash';
  static const String _geminiEndpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/$_geminiModel:generateContent';
  static const String _groqModel = 'openai/gpt-oss-20b';
  static const String _groqEndpoint =
      'https://api.groq.com/openai/v1/chat/completions';

  static void initialize({
    required String geminiApiKey,
    required String groqApiKey,
  }) {
    _geminiApiKey = geminiApiKey;
    _groqApiKey = groqApiKey;
    _initialized = true;
  }

  static void _assertInitialized() {
    if (!_initialized) {
      throw StateError(
        'AiConfig.initialize() must be called before use (see main.dart).',
      );
    }
  }

  /// Generic text-in/text-out call used by translation, AI agent, etc.
  /// Tries Gemini; on error or rate-limit, falls back to Groq.
  static Future<String> generateText({
    required String prompt,
    String? systemInstruction,
  }) async {
    _assertInitialized();

    try {
      return await _callGemini(
        prompt: prompt,
        systemInstruction: systemInstruction,
      );
    } catch (e) {
      // Fall back to Groq on any Gemini failure (rate-limit or otherwise).
      try {
        return await _callGroq(
          prompt: prompt,
          systemInstruction: systemInstruction,
        );
      } catch (fallbackError) {
        throw AiFailure(
          'Both Gemini and Groq calls failed. '
          'Gemini error: $e. Groq error: $fallbackError.',
        );
      }
    }
  }

  /// Plain REST call to Gemini's `generateContent` endpoint. [extraParts]
  /// lets [generateFromAudio] attach an inline-data part (audio bytes)
  /// alongside the text prompt — both text-only and audio-plus-text
  /// requests share this one implementation, same as the old SDK call
  /// handled both via `Content.text`/`Content.multi`.
  static Future<String> _callGemini({
    required String prompt,
    String? systemInstruction,
    List<Map<String, dynamic>>? extraParts,
  }) async {
    final body = <String, dynamic>{
      'contents': [
        {
          'parts': [
            {'text': prompt},
            ...?extraParts,
          ],
        },
      ],
      if (systemInstruction != null)
        'systemInstruction': {
          'parts': [
            {'text': systemInstruction},
          ],
        },
    };

    final response = await http.post(
      Uri.parse(_geminiEndpoint),
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': _geminiApiKey,
      },
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw AiFailure(
        'Gemini call failed with status ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final text = _extractGeminiText(decoded);
    if (text == null || text.isEmpty) {
      throw AiFailure('Gemini returned an empty response.');
    }
    return text;
  }

  /// Concatenates every text part of the first candidate — mirrors what
  /// the old SDK's `response.text` convenience getter did under the hood,
  /// since a JSON-mode response can occasionally split across parts.
  static String? _extractGeminiText(Map<String, dynamic> decoded) {
    final candidates = decoded['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) return null;
    final content = candidates[0]['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List<dynamic>?;
    if (parts == null) return null;
    final buffer = StringBuffer();
    for (final part in parts) {
      final text = (part as Map<String, dynamic>)['text'] as String?;
      if (text != null) buffer.write(text);
    }
    return buffer.toString();
  }

  static Future<String> _callGroq({
    required String prompt,
    String? systemInstruction,
  }) async {
    final messages = <Map<String, String>>[
      if (systemInstruction != null)
        {'role': 'system', 'content': systemInstruction},
      {'role': 'user', 'content': prompt},
    ];

    final response = await http.post(
      Uri.parse(_groqEndpoint),
      headers: {
        'Authorization': 'Bearer $_groqApiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': _groqModel,
        'messages': messages,
      }),
    );

    if (response.statusCode != 200) {
      throw AiFailure(
        'Groq call failed with status ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final content = decoded['choices']?[0]?['message']?['content'] as String?;
    if (content == null || content.isEmpty) {
      throw AiFailure('Groq returned an empty response.');
    }
    return content;
  }

  /// Native audio input (Gemini only — used by AI Feature 3, Phase 9).
  /// Groq's free tier does not offer a comparable native audio model,
  /// so voice transcription has no fallback path; failures surface as
  /// AiFailure and must be handled by the caller (voice_notes/ feature).
  static Future<String> generateFromAudio({
    required Uint8List audioBytes,
    required String mimeType,
    required String prompt,
  }) async {
    _assertInitialized();
    try {
      return await _callGemini(
        prompt: prompt,
        extraParts: [
          {
            'inlineData': {
              'mimeType': mimeType,
              'data': base64Encode(audioBytes),
            },
          },
        ],
      );
    } catch (e) {
      throw AiFailure('Gemini audio transcription failed: $e');
    }
  }
}
