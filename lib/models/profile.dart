/// Mirrors ERD.md `profiles` table exactly — do not add fields here
/// that aren't in ERD.md.
class Profile {
  final String id;
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final String preferredLanguage;
  final bool isOnline;
  final DateTime? lastSeenAt;
  final DateTime createdAt;

  const Profile({
    required this.id,
    required this.username,
    this.displayName,
    this.avatarUrl,
    this.preferredLanguage = 'en',
    this.isOnline = false,
    this.lastSeenAt,
    required this.createdAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      username: json['username'] as String,
      displayName: json['display_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      preferredLanguage: json['preferred_language'] as String? ?? 'en',
      isOnline: json['is_online'] as bool? ?? false,
      lastSeenAt: json['last_seen_at'] != null
          ? DateTime.parse(json['last_seen_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'display_name': displayName,
        'avatar_url': avatarUrl,
        'preferred_language': preferredLanguage,
        'is_online': isOnline,
        'last_seen_at': lastSeenAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };

  Profile copyWith({
    String? username,
    String? displayName,
    String? avatarUrl,
    String? preferredLanguage,
    bool? isOnline,
    DateTime? lastSeenAt,
  }) {
    return Profile(
      id: id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      preferredLanguage: preferredLanguage ?? this.preferredLanguage,
      isOnline: isOnline ?? this.isOnline,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      createdAt: createdAt,
    );
  }
}
