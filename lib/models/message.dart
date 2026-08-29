/// Mirrors ERD.md `messages` table exactly — do not add fields here
/// that aren't in ERD.md. Only 'text' messages are rendered by the UI
/// so far (Phase 2); other `type` values are modeled now so the shape
/// matches the DB, but their UI lands in Phase 5/9.
class Message {
  final String id;
  final String conversationId;
  final String? senderId; // nullable — null when is_ai_message is true
  final bool isAiMessage;
  final String type;
  final String? content;
  final String? mediaUrl;
  final String? originalLanguage;
  final String? translatedContent;
  final String? sharedContactId;
  final double? locationLat;
  final double? locationLng;
  final bool isLiveLocation;
  final DateTime? liveLocationExpiresAt;
  final String? voiceTranscript;
  final Map<String, dynamic>? voiceActions;
  final DateTime createdAt;

  const Message({
    required this.id,
    required this.conversationId,
    this.senderId,
    this.isAiMessage = false,
    required this.type,
    this.content,
    this.mediaUrl,
    this.originalLanguage,
    this.translatedContent,
    this.sharedContactId,
    this.locationLat,
    this.locationLng,
    this.isLiveLocation = false,
    this.liveLocationExpiresAt,
    this.voiceTranscript,
    this.voiceActions,
    required this.createdAt,
  });

  bool get isText => type == 'text';

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      senderId: json['sender_id'] as String?,
      isAiMessage: json['is_ai_message'] as bool? ?? false,
      type: json['type'] as String,
      content: json['content'] as String?,
      mediaUrl: json['media_url'] as String?,
      originalLanguage: json['original_language'] as String?,
      translatedContent: json['translated_content'] as String?,
      sharedContactId: json['shared_contact_id'] as String?,
      locationLat: (json['location_lat'] as num?)?.toDouble(),
      locationLng: (json['location_lng'] as num?)?.toDouble(),
      isLiveLocation: json['is_live_location'] as bool? ?? false,
      liveLocationExpiresAt: json['live_location_expires_at'] != null
          ? DateTime.parse(json['live_location_expires_at'] as String)
          : null,
      voiceTranscript: json['voice_transcript'] as String?,
      voiceActions: json['voice_actions'] as Map<String, dynamic>?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversation_id': conversationId,
        'sender_id': senderId,
        'is_ai_message': isAiMessage,
        'type': type,
        'content': content,
        'media_url': mediaUrl,
        'original_language': originalLanguage,
        'translated_content': translatedContent,
        'shared_contact_id': sharedContactId,
        'location_lat': locationLat,
        'location_lng': locationLng,
        'is_live_location': isLiveLocation,
        'live_location_expires_at': liveLocationExpiresAt?.toIso8601String(),
        'voice_transcript': voiceTranscript,
        'voice_actions': voiceActions,
        'created_at': createdAt.toIso8601String(),
      };
}
