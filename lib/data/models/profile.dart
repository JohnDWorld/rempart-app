import 'package:flutter/foundation.dart';

/// Modèle représentant un profil utilisateur
@immutable
class Profile {
  const Profile({
    required this.id,
    required this.username,
    required this.createdAt,
    required this.updatedAt,
    this.displayName,
    this.avatarUrl,
    this.bio,
    this.phone,
    this.isOnline = false,
    this.lastSeenAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      username: json['username'] as String,
      displayName: json['display_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      bio: json['bio'] as String?,
      phone: json['phone'] as String?,
      isOnline: json['is_online'] as bool? ?? false,
      lastSeenAt: json['last_seen_at'] != null
          ? DateTime.parse(json['last_seen_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  final String id;
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final String? bio;
  final String? phone;
  final bool isOnline;
  final DateTime? lastSeenAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Nom à afficher (displayName ou username)
  String get name => displayName ?? username;

  /// Convertir en Map JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'display_name': displayName,
      'avatar_url': avatarUrl,
      'bio': bio,
      'phone': phone,
      'is_online': isOnline,
      'last_seen_at': lastSeenAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Créer une copie avec des modifications
  Profile copyWith({
    String? id,
    String? username,
    String? displayName,
    String? avatarUrl,
    String? bio,
    String? phone,
    bool? isOnline,
    DateTime? lastSeenAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Profile(
      id: id ?? this.id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
      phone: phone ?? this.phone,
      isOnline: isOnline ?? this.isOnline,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Profile && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Profile(id: $id, username: $username)';
}
