// lib/features/voice_notes/data/voice_transcription_repository.dart
import 'dart:convert';
import 'dart:typed_data';

import '../../../config/ai_config.dart';
import '../../../core/errors/failure.dart';

/// A single extracted action item/reminder from a voice note transcript
/// (AI Feature 3, Phase 9). [time] is a short, human-readable time
/// reference exactly as implied by the transcript (e.g. "Thursday",
/// "5pm tomorrow") — null when the speaker didn't mention one. Stored
/// inside `messages.voice_actions` as `{"items": [...]}` (ERD.md's
/// jsonb column, wrapped in an object rather than a bare array so the
/// shape can grow later without a breaking migration — same reasoning
/// other jsonb/composite shapes in this codebase already use).
class VoiceActionItem {
  const VoiceActionItem({required this.title, this.time});

  final String title;
  final String? time;

  factory VoiceActionItem.fromJson(Map<String, dynamic> json) {
    return VoiceActionItem(
      title: json['title'] as String,
      time: json['time'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        if (time != null) 'time': time,
      };
}

/// Both AI calls behind AI Feature 3 (PRD.md §10): native-audio
/// transcription, then a second text-in/text-out pass over the
/// transcript to pull out action items. Same split as every other
/// feature's `data/` layer — prompt shape and response parsing live
/// here; the actual Gemini/Groq round trip only ever happens through
/// `AiConfig` (rules.md Rule 8).
class VoiceTranscriptionRepository {
  const VoiceTranscriptionRepository();

  /// Returned (internally) when Gemini heard the clip but there was no
  /// actual speech in it (silence, background noise only). [transcribe]
  /// converts this to an empty string for the caller — worth
  /// distinguishing from a hard failure in prompting, not worth a
  /// separate case for callers to handle.
  static const noSpeechSentinel = '[no speech detected]';

  static const _transcribePrompt =
      'Transcribe the spoken words in this voice note exactly as said, '
      'in the language it was spoken in. Return ONLY the transcript '
      'text - no preamble, no quotation marks, no speaker labels, no '
      'timestamps. If there is no audible speech in the clip (silence '
      'or noise only), respond with exactly: $noSpeechSentinel';

  /// Gemini native audio input — no Groq fallback (see
  /// `AiConfig.generateFromAudio`'s doc comment; Groq's free tier has
  /// no comparable audio model). [audioBytes] are the same bytes
  /// already captured for upload, passed straight through — no need to
  /// re-download from Storage for this call.
  Future<String> transcribe(Uint8List audioBytes) async {
    final raw = await AiConfig.generateFromAudio(
      audioBytes: audioBytes,
      // The `record` package encodes to AAC-LC inside an .m4a (MP4)
      // container (see VoiceNoteRepository) — 'audio/mp4' is Gemini's
      // documented MIME type for that container, distinct from
      // 'audio/aac' (raw ADTS stream, no container).
      mimeType: 'audio/mp4',
      prompt: _transcribePrompt,
    );
    final trimmed = raw.trim();
    return trimmed == noSpeechSentinel ? '' : trimmed;
  }

  static const _extractionSystemInstruction =
      'You extract action items and reminders from a single voice note '
      'transcript inside a chat app. Read the transcript and identify '
      'concrete tasks, plans, deadlines, or reminders the speaker '
      'mentions - things they or the listener would plausibly want as '
      'a to-do. Ignore casual remarks that describe no actual task. '
      'For each item, give a short "title" (a few words) and, only if '
      'the transcript implies a specific time/day/deadline for it, a '
      'short "time" string in the speaker\'s own words (e.g. '
      '"Thursday", "5pm tomorrow", "end of the month") - otherwise '
      'omit "time" entirely. If there are no actionable items, return '
      'an empty list. Respond with ONLY raw JSON, no markdown fences, '
      'no commentary, in exactly this shape: '
      '{"actions":[{"title":"<string>","time":"<string, optional>"}]}';

  /// Second AI pass, over the transcript *text* (not the audio) — a
  /// plain `AiConfig.generateText` call, so this one does get the Groq
  /// fallback. Returns an empty list (never throws for "nothing
  /// found") when the transcript has no actionable content.
  Future<List<VoiceActionItem>> extractActions(String transcript) async {
    final raw = await AiConfig.generateText(
      prompt: transcript,
      systemInstruction: _extractionSystemInstruction,
    );
    try {
      final match = RegExp(r'\{[\s\S]*\}').firstMatch(raw);
      if (match == null) return const [];
      final decoded = jsonDecode(match.group(0)!) as Map<String, dynamic>;
      final rawActions = decoded['actions'] as List<dynamic>? ?? [];
      return rawActions
          .whereType<Map<String, dynamic>>()
          .where((a) => (a['title'] as String?)?.trim().isNotEmpty ?? false)
          .map(VoiceActionItem.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
