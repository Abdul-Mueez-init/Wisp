import 'dart:typed_data';

import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../core/errors/failure.dart';

/// Shared AI client wrapper per architecture.md "AI Integration Pattern":
/// tries Gemini first, falls back to Groq on rate-limit/error.
/// Feature code (translation/, ai_agent/, voice_notes/) must call
/// AiConfig methods only — never instantiate Gemini/Groq SDKs directly
/// (rules.md Rule 8).
///
/// NOTE: this is the Phase 0 skeleton per plan.md ("fallback logic
/// stubbed"). Feature-specific prompt construction (translation prompts,
/// agent context-window assembly, voice transcription/action-extraction
/// prompts) is intentionally NOT here — those land in Phases 7/8/9.
class AiConfig {
  AiConfig._();

  static late final String _geminiApiKey;
  static late final String _groqApiKey;
  static bool _initialized = false;

  static const String _geminiModel = 'gemini-1.5-flash';
  static const String _groqModel = 'llama-3.1-8b-instant';
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

  static Future<String> _callGemini({
    required String prompt,
    String? systemInstruction,
  }) async {
    final model = GenerativeModel(
      model: _geminiModel,
      apiKey: _geminiApiKey,
      systemInstruction:
          systemInstruction != null ? Content.system(systemInstruction) : null,
    );
    final response = await model.generateContent([Content.text(prompt)]);
    final text = response.text;
    if (text == null || text.isEmpty) {
      throw AiFailure('Gemini returned an empty response.');
    }
    return text;
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
      final model = GenerativeModel(model: _geminiModel, apiKey: _geminiApiKey);
      final response = await model.generateContent([
        Content.multi([
          TextPart(prompt),
          DataPart(mimeType, audioBytes),
        ]),
      ]);
      final text = response.text;
      if (text == null || text.isEmpty) {
        throw AiFailure('Gemini audio call returned an empty response.');
      }
      return text;
    } catch (e) {
      throw AiFailure('Gemini audio transcription failed: $e');
    }
  }
}
