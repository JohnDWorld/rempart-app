import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Configuration des mises à jour de l'application, hors magasin.
///
/// Vide, **rien n'est activé** : ni vérification périodique, ni bouton dans
/// les paramètres, ni requête réseau. C'est ce qui permet de produire un build
/// destiné à Google Play, dont le règlement interdit à une application de se
/// mettre à jour elle-même.
abstract class UpdateConstants {
  /// URL du manifeste `latest.json` publié par le serveur de mises à jour.
  static String get manifestUrl => dotenv.env['UPDATE_MANIFEST_URL']?.trim() ?? '';

  /// La fonctionnalité est-elle activée dans ce build ?
  static bool get actif => manifestUrl.isNotEmpty;

  /// Délai entre deux vérifications automatiques.
  ///
  /// La vérification a lieu au lancement, pas sur une alarme : une mise à jour
  /// ne sert qu'au moment où l'utilisateur ouvre l'application, donc réveiller
  /// le téléphone toutes les six heures dépenserait de la batterie pour un
  /// résultat qu'il ne verrait pas plus tôt.
  static const Duration intervalle = Duration(hours: 6);
}

/// Faut-il interroger le serveur maintenant ?
///
/// `null` (jamais vérifié) répond oui : la première ouverture après une
/// installation est justement le moment où l'on veut savoir.
bool doitVerifier({
  required DateTime? derniere,
  required DateTime maintenant,
  Duration intervalle = UpdateConstants.intervalle,
}) {
  if (derniere == null) return true;
  return maintenant.difference(derniere) >= intervalle;
}
