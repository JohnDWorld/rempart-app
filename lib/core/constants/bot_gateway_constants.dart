import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Configuration de la Bot Gateway (API des bots utilisateurs).
///
/// La gateway est la "Bot API" de Rempart : elle permet de créer des bots
/// hébergés côté serveur et de les piloter depuis un agent externe. La valeur
/// est chargée depuis le fichier .env (voir .env.example).
abstract class BotGatewayConstants {
  /// URL de base de la gateway (ex. http://100.64.0.10:8300).
  static String get baseUrl => dotenv.env['BOT_GATEWAY_URL'] ?? '';
}
