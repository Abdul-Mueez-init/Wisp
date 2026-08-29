/// Mirrors ERD.md `calls` table exactly — do not add fields here that
/// aren't in ERD.md. `started_at` is set at call-creation ("ringing")
/// time, not at connect time — see the Phase 10 migration note, since
/// `calls` has no separate `created_at` column to order history by.
class Call {
  final String id;
  final String conversationId;
  final String callerId;
  final String type; // 'audio' | 'video'
  final String
      status; // 'ringing' | 'ongoing' | 'ended' | 'missed' | 'declined'
  final DateTime? startedAt;
  final DateTime? endedAt;

  const Call({
    required this.id,
    required this.conversationId,
    required this.callerId,
    required this.type,
    required this.status,
    this.startedAt,
    this.endedAt,
  });

  bool get isVideo => type == 'video';
  bool get isActive => status == 'ringing' || status == 'ongoing';
  bool get isMissedOrDeclined => status == 'missed' || status == 'declined';

  Duration? get duration {
    if (startedAt == null || endedAt == null) return null;
    if (status != 'ended') return null;
    return endedAt!.difference(startedAt!);
  }

  Call copyWith({
    String? status,
    DateTime? startedAt,
    DateTime? endedAt,
  }) {
    return Call(
      id: id,
      conversationId: conversationId,
      callerId: callerId,
      type: type,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
    );
  }

  factory Call.fromJson(Map<String, dynamic> json) {
    return Call(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      callerId: json['caller_id'] as String,
      type: json['type'] as String,
      status: json['status'] as String,
      startedAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'] as String)
          : null,
      endedAt: json['ended_at'] != null
          ? DateTime.parse(json['ended_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversation_id': conversationId,
        'caller_id': callerId,
        'type': type,
        'status': status,
        'started_at': startedAt?.toIso8601String(),
        'ended_at': endedAt?.toIso8601String(),
      };
}
