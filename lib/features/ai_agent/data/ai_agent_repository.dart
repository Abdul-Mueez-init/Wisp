// lib/features/ai_agent/data/ai_agent_repository.dart
import '../../../config/ai_config.dart';
import '../../../models/message.dart';

/// AI Feature 2 (PRD.md §10) — the embedded agent's own prompt
/// construction. Same split as `TranslationRepository`: this owns the
/// prompt shape and response handling, the actual Gemini/Groq round
/// trip still only ever happens through `AiConfig` (rules.md Rule 8).
/// Unlike translation, a reply is free-form text, not structured JSON,
/// so this calls `AiConfig.generateText` directly with a transcript
/// prompt and returns the raw reply.
class AiAgentRepository {
  const AiAgentRepository();

  /// The literal trigger for PRD.md's "@mention the AI inside any
  /// 1-on-1 or group chat" access path. A whole-word match on "@wisp"
  /// (case-insensitive) — deliberately not a bare "wisp" match, so an
  /// ordinary sentence that happens to mention the app by name doesn't
  /// summon the agent uninvited.
  static final RegExp _mentionPattern =
      RegExp(r'@wisp\b', caseSensitive: false);

  static bool mentionsAgent(String text) => _mentionPattern.hasMatch(text);

  static const _systemInstruction =
      'You are Wisp, a helpful, friendly AI assistant embedded directly '
      'inside the Wisp messaging app. You are given a transcript of the '
      'most recent messages in an ongoing chat, oldest first, each line '
      'prefixed with who sent it. Reply naturally to the conversation as '
      '"Wisp" would - warm, concise, and directly useful. Do not prefix '
      'your reply with "Wisp:" or any name, and do not repeat the '
      'transcript back - write only the message content itself.';

  /// Builds a transcript from [history] (oldest first, per PRD.md's
  /// "context of recent chat history... not just the single message it
  /// was mentioned in") and asks Gemini/Groq to continue it as "Wisp".
  /// [myId] labels the current user's own lines as "You"; every other
  /// human sender is resolved through [senderLabels] (fetched by the
  /// caller — this repository only builds the prompt, per the same
  /// split `TranslationRepository` already uses).
  Future<String> generateReply({
    required List<Message> history,
    required String? myId,
    required Map<String, String> senderLabels,
  }) async {
    final transcript = history
        .map((m) => '${_labelFor(m, myId, senderLabels)}: ${_describe(m)}')
        .join('\n');

    final prompt = '$transcript\nWisp:';
    final reply = await AiConfig.generateText(
      prompt: prompt,
      systemInstruction: _systemInstruction,
    );
    return reply.trim();
  }

  String _labelFor(
    Message m,
    String? myId,
    Map<String, String> senderLabels,
  ) {
    if (m.isAiMessage) return 'Wisp';
    if (m.senderId == myId) return 'You';
    return senderLabels[m.senderId] ?? 'Someone';
  }

  /// Non-text message types get a short bracketed description instead
  /// of being skipped outright, so the agent has situational context
  /// (e.g. "shared a location") without needing multimodal input in
  /// this call. `voice_transcript` (AI Feature 3, Phase 9) is used
  /// when already present, so a voice note's real content counts
  /// toward context once that phase lands — the ERD.md column already
  /// exists today, nothing to add later for this to pick it up.
  String _describe(Message m) {
    switch (m.type) {
      case 'text':
        return m.content ?? '';
      case 'image':
        return m.content?.isNotEmpty == true
            ? '[sent an image: ${m.content}]'
            : '[sent an image]';
      case 'video':
        return m.content?.isNotEmpty == true
            ? '[sent a video: ${m.content}]'
            : '[sent a video]';
      case 'voice':
        return m.voiceTranscript != null
            ? '[voice note: ${m.voiceTranscript}]'
            : '[sent a voice note]';
      case 'document':
        return '[sent a document]';
      case 'contact':
        return '[shared a contact]';
      case 'location_current':
      case 'location_live':
        return '[shared a location]';
      default:
        return '[message]';
    }
  }
}
