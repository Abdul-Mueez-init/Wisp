/// Mirrors ERD.md `message_status` table exactly.
class MessageStatus {
  final String id;
  final String messageId;
  final String userId; // recipient
  final String status; // 'sent' | 'delivered' | 'read'
  final DateTime updatedAt;

  const MessageStatus({
    required this.id,
    required this.messageId,
    required this.userId,
    required this.status,
    required this.updatedAt,
  });

  factory MessageStatus.fromJson(Map<String, dynamic> json) {
    return MessageStatus(
      id: json['id'] as String,
      messageId: json['message_id'] as String,
      userId: json['user_id'] as String,
      status: json['status'] as String,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
