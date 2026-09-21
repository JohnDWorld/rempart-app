import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Configuration Matrix/Synapse
///
/// Les valeurs sont chargees depuis le fichier .env
/// Voir .env.example pour le template
abstract class MatrixConstants {
  /// Mode developpement local (true) ou production (false)
  static bool get isLocal => dotenv.env['IS_LOCAL']?.toLowerCase() == 'true';

  /// URL du homeserver Matrix (depuis .env)
  static String get homeserver => dotenv.env['MATRIX_HOMESERVER'] ?? '';

  /// Domaine du serveur Matrix (server_name de Synapse)
  /// Différent de l'URL du homeserver quand on utilise un tunnel local
  static String get domain => dotenv.env['MATRIX_DOMAIN'] ?? _extractDomain();

  /// Extrait le domaine de l'URL du homeserver si MATRIX_DOMAIN n'est pas défini
  static String _extractDomain() {
    final url = Uri.tryParse(homeserver);
    return url?.host ?? 'localhost';
  }

  /// Nom de l'application (affiche dans les sessions)
  static const String applicationName = 'Rempart Messenger';

  /// Identifiant de l'appareil (genere automatiquement si null)
  static const String? deviceId = null;

  /// Duree de synchronisation initiale (en secondes)
  static const int initialSyncTimeout = 30;

  /// Duree de synchronisation continue (en secondes)
  static const int syncTimeout = 30;

  /// Nombre de messages a charger par defaut
  static const int defaultMessageLimit = 50;
}
