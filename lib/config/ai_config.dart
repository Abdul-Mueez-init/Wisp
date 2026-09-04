import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/errors/failure.dart';

/// Shared AI client wrapper per architecture.md "AI Integration Pattern":
/// tries Gemini first, falls back to Groq on rate-limit/error.
/// Feature code (translation/, ai_agent/, voice_notes/) must call
/// AiConfig methods only — never instantiate Gemini/Groq SDKs directly
/// (rules.md Rule 8).
class AiConfig {
  AiConfig._();

  static late final String _geminiApiKey;
  static late final String _groqApiKey;
  static bool _initialized = false;

  static const String _geminiModel = 'gemini-3.6-flash';
  static const String _geminiEndpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/$_geminiModel:generateContent';
  static const String _groqModel = 'openai/gpt-oss-20b';
  static const String _groqEndpoint =
      'https://api.groq.com/openai/v1/chat/completions';
  static const String _groqAudioEndpoint =
      'https://api.groq.com/openai/v1/audio/transcriptions';
  static const String _groqAudioModel = 'whisper-large-v3-turbo';

  // Standard client User-Agent preventing Cloudflare 403 (Error 1010) on api.groq.com
  static const String _userAgent =
      'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  static void initialize({
    required String geminiApiKey,
    required String groqApiKey,
  }) {
    _geminiApiKey = geminiApiKey.trim().replaceAll('"', '').replaceAll("'", '');
    _groqApiKey = groqApiKey.trim().replaceAll('"', '').replaceAll("'", '');
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
      Uri.parse('$_geminiEndpoint?key=$_geminiApiKey'),
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

  static Future<String> _callGroqWhisper({
    required Uint8List audioBytes,
    String filename = 'audio.m4a',
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse(_groqAudioEndpoint),
    );
    request.headers['Authorization'] = 'Bearer $_groqApiKey';
    request.fields['model'] = _groqAudioModel;
    request.fields['response_format'] = 'json';

    request.files.add(http.MultipartFile.fromBytes(
      'file',
      audioBytes,
      filename: filename,
    ));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw AiFailure(
        'Groq Whisper failed with status ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final text = decoded['text'] as String?;
    if (text == null || text.trim().isEmpty) {
      throw const AiFailure('Groq Whisper returned an empty transcript.');
    }
    return text.trim();
  }

  /// Audio transcription: tries Gemini native audio first, and seamlessly
  /// falls back to Groq Whisper Large V3 Turbo on error/rate-limit/503.
  static Future<String> generateFromAudio({
    required Uint8List audioBytes,
    required String mimeType,
    required String prompt,
    String filename = 'audio.m4a',
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
    } catch (geminiError) {
      try {
        return await _callGroqWhisper(
          audioBytes: audioBytes,
          filename: filename,
        );
      } catch (groqError) {
        throw AiFailure(
          'Both Gemini audio and Groq Whisper transcription failed. '
          'Gemini error: $geminiError. Groq error: $groqError.',
        );
      }
    }
  }
}
