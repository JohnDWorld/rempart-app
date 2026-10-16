import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/supabase_constants.dart';
import '../models/profile.dart';

/// Un nom d'utilisateur refusé par la base ; [raison] vaut `pris` ou l'une
/// des règles (`longueur`, `caracteres`, `reserve`).
class NomUtilisateurRefuse implements Exception {
  const NomUtilisateurRefuse(this.raison);

  final String raison;
}

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

  /// Récupérer un profil par ID.
  ///
  /// Par la fonction bornée `profils_par_id`, pas par la table : la lecture
  /// directe des profils des autres se referme (migration du 2026-10-15), et
  /// tout compte connecté pouvait jusque-là tirer l'annuaire entier.
  Future<Profile?> getProfile(String userId) async {
    final profils = await profilsParId([userId]);
    return profils.isEmpty ? null : profils.first;
  }

  /// Les profils de ces identifiants (ceux que portent les identifiants
  /// Matrix `@u_<id>`). La base en rend deux cents au plus.
  Future<List<Profile>> profilsParId(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final reponse =
        await _client.rpc<List<dynamic>>('profils_par_id', params: {'ids': ids});
    return _profils(reponse);
  }

  /// Le profil de qui porte exactement ce nom d'utilisateur (casse ignorée).
  ///
  /// C'est la seule façon de trouver quelqu'un avec qui l'on ne partage
  /// encore rien : le nom affiché ne se cherche que parmi ses contacts, sans
  /// quoi l'annuaire se parcourrait lettre par lettre.
  Future<Profile?> getProfileByUsername(String username) async {
    final reponse = await _client.rpc<List<dynamic>>(
      'profil_par_nom_utilisateur',
      params: {'nom': username},
    );
    final profils = _profils(reponse);
    return profils.isEmpty ? null : profils.first;
  }

  /// Null si [nom] est libre et permis, sinon la raison du refus (`pris`, ou
  /// l'une des règles, voir `messageRefusNomUtilisateur`). Répond aussi sans
  /// compte : on choisit son nom avant que l'inscription n'ouvre une session.
  Future<String?> nomUtilisateurRefuse(String nom) =>
      _client.rpc<String?>('nom_utilisateur_disponible', params: {'nom': nom});

  /// Change son nom d'utilisateur. Lève [NomUtilisateurRefuse] si la base le
  /// refuse : pris (contrainte d'unicité) ou hors des règles (le déclencheur
  /// `normaliser_nom_utilisateur`, qui lève `nom_utilisateur_<raison>`).
  Future<void> changerNomUtilisateur(String nom) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Utilisateur non connecté');
    try {
      await _client.from('profiles').update({'username': nom}).eq('id', userId);
    } on PostgrestException catch (e) {
      if (e.code == '23505') throw const NomUtilisateurRefuse('pris');
      if (e.code == '23514' && e.message.startsWith('nom_utilisateur_')) {
        throw NomUtilisateurRefuse(
          e.message.substring('nom_utilisateur_'.length),
        );
      }
      rethrow;
    }
  }

  List<Profile> _profils(List<dynamic> lignes) => [
        for (final ligne in lignes)
          Profile.fromJson(ligne as Map<String, dynamic>),
      ];

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

  /// Stream des changements de profil
  Stream<Profile> watchProfile(String userId) {
    return _client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', userId)
        .map((data) => Profile.fromJson(data.first));
  }
}
