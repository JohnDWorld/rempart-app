import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/supabase_constants.dart';
import '../models/profile.dart';

/// Service pour la gestion des profils utilisateurs
class ProfileService {
  ProfileService(this._client);

  final SupabaseClient _client;

  /// Récupérer le profil de l'utilisateur courant
  Future<Profile?> getCurrentProfile() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    return getProfile(userId);
  }

  /// Récupérer un profil par ID
  Future<Profile?> getProfile(String userId) async {
    final response =
        await _client.from('profiles').select().eq('id', userId).maybeSingle();

    if (response == null) return null;
    return Profile.fromJson(response);
  }

  /// Récupérer un profil par username
  Future<Profile?> getProfileByUsername(String username) async {
    final response = await _client
        .from('profiles')
        .select()
        .eq('username', username)
        .maybeSingle();

    if (response == null) return null;
    return Profile.fromJson(response);
  }

  /// Rechercher des profils par nom ou username
  Future<List<Profile>> searchProfiles(String query) async {
    final response = await _client
        .from('profiles')
        .select()
        .or('username.ilike.%$query%,display_name.ilike.%$query%')
        .neq('id', _client.auth.currentUser?.id ?? '')
        .limit(20);

    return (response as List)
        .map((p) => Profile.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  /// Mettre à jour le profil
  Future<Profile> updateProfile({
    String? displayName,
    String? bio,
    String? phone,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Utilisateur non connecté');

    final updates = <String, dynamic>{};
    if (displayName != null) updates['display_name'] = displayName;
    if (bio != null) updates['bio'] = bio;
    if (phone != null) updates['phone'] = phone;

    final response = await _client
        .from('profiles')
        .update(updates)
        .eq('id', userId)
        .select()
        .single();

    return Profile.fromJson(response);
  }

  /// Mettre à jour l'avatar
  Future<String> updateAvatar(File imageFile) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Utilisateur non connecté');

    final fileExt = imageFile.path.split('.').last;
    final fileName = '$userId/avatar.$fileExt';

    // Upload l'image
    await _client.storage.from(SupabaseConstants.avatarsBucket).upload(
        fileName, imageFile,
        fileOptions: const FileOptions(upsert: true));

    // Récupérer l'URL publique. Le fichier garde le même nom d'une photo à
    // l'autre, donc sans ce suffixe l'URL ne changerait pas et les caches
    // d'images continueraient d'afficher l'ancienne.
    final avatarUrl = '${_client.storage.from(SupabaseConstants.avatarsBucket)
        .getPublicUrl(fileName)}?v=${DateTime.now().millisecondsSinceEpoch}';

    // Mettre à jour le profil
    await _client
        .from('profiles')
        .update({'avatar_url': avatarUrl}).eq('id', userId);

    return avatarUrl;
  }

  /// Supprimer l'avatar
  Future<void> deleteAvatar() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Utilisateur non connecté');

    // Lister et supprimer les fichiers dans le dossier de l'utilisateur
    final files = await _client.storage
        .from(SupabaseConstants.avatarsBucket)
        .list(path: userId);

    if (files.isNotEmpty) {
      final paths = files.map((f) => '$userId/${f.name}').toList();
      await _client.storage.from(SupabaseConstants.avatarsBucket).remove(paths);
    }

    // Mettre à jour le profil
    await _client
        .from('profiles')
        .update({'avatar_url': null}).eq('id', userId);
  }

  /// Mettre à jour le statut en ligne
  Future<void> setOnlineStatus({required bool isOnline}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    await _client.from('profiles').update({
      'is_online': isOnline,
      'last_seen_at': DateTime.now().toIso8601String(),
    }).eq('id', userId);
  }

  /// Stream des changements de profil
  Stream<Profile> watchProfile(String userId) {
    return _client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', userId)
        .map((data) => Profile.fromJson(data.first));
  }
}
