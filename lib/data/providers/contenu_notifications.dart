import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// L'utilisateur veut-il lire ses messages dans les notifications ?
///
/// À lui d'en décider : un aperçu sur l'écran verrouillé est commode chez soi,
/// beaucoup moins dans un train. Désactivé, la notification se réduit à
/// « Nouveau message », sans expéditeur ni texte.
///
/// La valeur est relue au démarrage et injectée par `main.dart` (voir
/// `chargerContenuNotifications`) : sans cela, la première notification suivant
/// un lancement afficherait le contenu d'un utilisateur qui n'en veut pas.
final contenuNotificationsProvider = StateProvider<bool>((ref) => true);

const _cle = 'notifications_contenu';

/// Lit le réglage enregistré. Contenu affiché par défaut, y compris si rien
/// n'est lisible : c'est le comportement historique de l'app.
Future<bool> chargerContenuNotifications() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_cle) ?? true;
  } catch (_) {
    return true;
  }
}

/// Enregistre le réglage. Best-effort : un échec d'écriture ne doit pas
/// empêcher le changement, déjà appliqué au service de notifications.
Future<void> enregistrerContenuNotifications({required bool afficher}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cle, afficher);
  } catch (_) {
    // Sans persistance, le choix vaut pour la session : mieux que de le
    // refuser.
  }
}
