import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Retient [brut] s'il s'agit d'une adresse de soutien exploitable, sinon rend
/// une chaîne vide, ce qui éteint la fonctionnalité.
///
/// Seul `https` est accepté. La valeur vient du `.env`, donc de nous, mais un
/// `http://` sur une page qui parle d'argent serait un mauvais signal, et un
/// schéma exotique n'a rien à faire dans un `launchUrl`. Le `trim` couvre le
/// fichier édité à la main, où « DON_URL=   » ferait apparaître une entrée
/// menant dans le vide.
///
/// Fonction séparée pour être testable : `dotenv` a besoin du binding Flutter
/// et d'un asset, la validation non.
String urlDeSoutienValide(String? brut) {
  final url = brut?.trim() ?? '';
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return '';
  return url;
}

/// Constantes générales de l'application
abstract class AppConstants {
  /// Nom de l'application
  static const String appName = 'Rempart';

  /// Adresse de la boutique à agents, où l'on commande un agent sur mesure.
  ///
  /// Dans le .env pour suivre un changement de page ou de domaine sans
  /// reprendre le code ; la valeur de repli évite un écran de promotion dont
  /// le bouton ne mènerait nulle part.
  static String get boutiqueAgentsUrl {
    final url = dotenv.env['BOUTIQUE_AGENTS_URL']?.trim() ?? '';
    return url.isEmpty ? 'https://la-boutique-a-agents.com' : url;
  }

  /// Dépôt public du code de l'application.
  ///
  /// Une constante et non une variable d'environnement : ce n'est pas un
  /// réglage mais une obligation. L'application se lie à du code sous AGPL,
  /// donc quiconque reçoit le binaire doit pouvoir obtenir la source
  /// correspondante ; une adresse que le `.env` pourrait vider ferait
  /// disparaître l'offre sans que personne s'en aperçoive.
  static const String codeSourceUrl =
      'https://github.com/JohnDWorld/rempart-app';

  /// Adresse à laquelle écrire pour une question de commande.
  ///
  /// Celle de la boutique, et d'elle seule : le contact légal et RGPD de
  /// Rempart reste distinct (voir les documents légaux). Une constante et non
  /// une variable d'environnement, contrairement à l'URL : la page de commande
  /// peut déménager, l'adresse de la boutique non.
  static const String boutiqueAgentsEmail = 'contact@la-boutique-a-agents.com';

  /// Adresse de la page de soutien, où l'on peut faire un don.
  ///
  /// Vide, la fonctionnalité n'existe pas : aucune entrée dans les réglages,
  /// aucun lien. C'est le même parti que `UPDATE_MANIFEST_URL`, et il sert ici
  /// à deux choses.
  ///
  /// D'abord tant que la page n'est pas en ligne, une entrée mènerait dans le
  /// vide. Ensuite les boutiques : un « soutenez le développeur » encaissé
  /// dans l'application est, pour Apple, un achat de contenu numérique, donc
  /// un achat intégré, donc une commission. Le don se fait sur le web, et
  /// l'application n'en porte qu'un lien.
  ///
  /// Corollaire utile : le discours de la page se réécrit sans republier
  /// l'application ni repasser devant un examinateur.
  static String get donUrl => urlDeSoutienValide(dotenv.env['DON_URL']);

  /// Le soutien est-il proposé ? Faux tant que `DON_URL` n'est pas renseignée.
  static bool get donDisponible => donUrl.isNotEmpty;

  /// Version de l'application
  static const String appVersion = '1.0.0';

  /// Durée d'animation par défaut
  static const Duration animationDuration = Duration(milliseconds: 300);

  /// Durée du splash screen
  /// Durée minimale d'affichage du logo au démarrage.
  ///
  /// Ce n'est plus le temps d'attente : l'écran de démarrage attend l'amorçage
  /// réel des services. Il ne reste qu'un plancher, pour que le logo ne
  /// clignote pas quand tout est déjà chargé.
  static const Duration splashDuration = Duration(milliseconds: 600);

  /// Longueur minimale du mot de passe.
  ///
  /// 10 et non 8 : le serveur ne voit plus qu'une dérivation lente du mot de
  /// passe, mais un exploitant malveillant pourrait encore la soumettre à des
  /// essais en série pour retrouver le coffre de clés. Chaque caractère de plus
  /// multiplie le nombre d'essais. Ne s'impose qu'à la création et au
  /// changement, jamais à la connexion.
  static const int minPasswordLength = 10;

  /// Longueur maximale du nom d'affichage
  static const int maxDisplayNameLength = 50;

  /// Longueur maximale d'un message
  static const int maxMessageLength = 4000;
}
