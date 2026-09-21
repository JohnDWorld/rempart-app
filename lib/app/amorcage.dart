import 'package:flutter/foundation.dart';

import '../data/services/archive_service.dart';
import '../data/services/matrix_service.dart';
import '../data/services/push_service.dart';
import '../data/services/reinitialisation_e2e.dart';

/// Prépare les services lourds **derrière** l'écran de démarrage.
///
/// Base Matrix, chiffrement et push demandent plus d'une seconde. Les attendre
/// avant `runApp` laissait l'écran noir pendant tout ce temps : Flutter ne
/// dessine rien tant que `runApp` n'est pas appelé, et le fond hérité du thème
/// Android est noir en mode sombre. L'utilisateur voyait donc un écran mort,
/// sans logo ni indication.
///
/// L'amorçage démarre une fois, dès le lancement, et l'écran de démarrage
/// attend ce même futur.
abstract final class Amorcage {
  static Future<void>? _encours;

  /// Lance l'amorçage au premier appel, puis renvoie toujours le même futur.
  static Future<void> get futur => _encours ??= _executer();

  static Future<void> _executer() async {
    // Chaque service est isolé : qu'un seul échoue (stockage en lecture seule,
    // distributeur de push absent) ne doit pas retenir l'application sur son
    // écran de démarrage. Mieux vaut ouvrir en mode dégradé que ne pas ouvrir.
    await _tenter('archives', ArchiveService.instance.init);
    // Avant Matrix : le premier fil affiché doit déjà connaître la coupure,
    // sinon il montre une fois les messages qu'on vient de renoncer à lire.
    await _tenter('coupure E2E', ReinitialisationE2e.charger);
    await _tenter('matrix', MatrixService.instance.init);
    await _tenter('push', PushService.instance.init);
  }

  static Future<void> _tenter(
    String quoi,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (e) {
      debugPrint('Amorçage: $quoi a échoué, on continue sans : $e');
    }
  }
}
