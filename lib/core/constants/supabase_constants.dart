import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Configuration Supabase & Matrix
///
/// Les valeurs sont chargees depuis le fichier .env
/// Voir .env.example pour le template
abstract class SupabaseConstants {
  /// Mode developpement local (true) ou production (false)
  static bool get isLocal => dotenv.env['IS_LOCAL']?.toLowerCase() == 'true';

  /// URL Supabase (depuis .env)
  static String get url => dotenv.env['SUPABASE_URL'] ?? '';

  /// Cle anonyme Supabase (depuis .env)
  static String get anonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  /// Schema PostgREST cible pour les tables applicatives (profiles,
  /// matrix_credentials). Par defaut `public` (Supabase local via les
  /// migrations). Sur le serveur johnserver, le projet est isole dans un
  /// schema dedie `rempart` (base partagee multi-projets) : mettre
  /// SUPABASE_SCHEMA=rempart dans le .env correspondant.
  static String get schema =>
      dotenv.env['SUPABASE_SCHEMA']?.trim().isNotEmpty ?? false
          ? dotenv.env['SUPABASE_SCHEMA']!.trim()
          : 'public';

  /// URL du homeserver Matrix (depuis .env)
  static String get matrixHomeserver => dotenv.env['MATRIX_HOMESERVER'] ?? '';

  /// Email pre-rempli sur l'ecran de connexion tant qu'aucune connexion n'a
  /// encore eu lieu sur cet appareil (confort de developpement : survit a une
  /// reinstallation, contrairement a l'email memorise). Vide en production.
  static String get defaultLoginEmail =>
      dotenv.env['DEFAULT_LOGIN_EMAIL']?.trim() ?? '';

  /// Nom du bucket pour les avatars
  static const String avatarsBucket = 'avatars';

  /// Nom du bucket pour les pieces jointes
  static const String attachmentsBucket = 'attachments';
}
