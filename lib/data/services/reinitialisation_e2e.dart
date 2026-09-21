import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Retient l'instant où le coffre de clés a été recréé sans sa clé de
/// récupération.
///
/// Tout ce qui a été reçu avant cet instant est chiffré avec des clés que plus
/// personne ne détient : ces messages ne redeviendront jamais lisibles. Les
/// laisser dans le fil remplirait chaque conversation de « Could not decrypt »,
/// que l'utilisateur lirait comme une panne de Rempart alors que c'est la
/// conséquence, annoncée deux fois, du choix qu'il vient de faire.
///
/// La coupure est locale, et c'est voulu : les autres appareils de la même
/// personne, s'ils ont gardé leurs clés, continuent d'afficher l'historique.
/// Rien n'est effacé côté serveur, seul l'affichage de cet appareil s'aligne
/// sur ce qu'il sait réellement lire.
abstract final class ReinitialisationE2e {
  static const _cle = 'e2e_reinitialise_le';

  static DateTime? _date;

  /// Instant de la dernière réinitialisation sans clé, ou `null`.
  static DateTime? get date => _date;

  /// À appeler au démarrage, avant le premier affichage d'un fil.
  static Future<void> charger() async {
    final prefs = await SharedPreferences.getInstance();
    final brut = prefs.getString(_cle);
    _date = brut == null ? null : DateTime.tryParse(brut);
  }

  /// Pose la coupure à maintenant.
  static Future<void> marquer() async {
    final maintenant = DateTime.now();
    _date = maintenant;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cle, maintenant.toIso8601String());
    } catch (e) {
      // La coupure vaut au moins pour cette session : échouer ici ne doit pas
      // faire échouer une réinitialisation par ailleurs réussie.
      debugPrint('Réinitialisation E2E : coupure non enregistrée ($e)');
    }
  }

  /// Vrai si un message daté de [quand] précède la coupure, donc s'il est
  /// définitivement illisible sur cet appareil.
  static bool avantLaCoupure(DateTime quand, {DateTime? coupure}) {
    final reference = coupure ?? _date;
    return reference != null && quand.isBefore(reference);
  }

  /// Pour les tests : remet l'état en mémoire à zéro.
  @visibleForTesting
  static void oublier() => _date = null;
}
