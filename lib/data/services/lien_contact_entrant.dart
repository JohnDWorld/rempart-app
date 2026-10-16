import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import '../../core/plateforme.dart';
import '../../core/utils/nom_utilisateur.dart';

/// Les liens de contact qui ouvrent Rempart
/// (`https://app.rempart-messenger.fr/contact/<nom>`).
///
/// Sur Android, le lien d'application vérifié les remet à l'application
/// installée ; dans le navigateur, c'est l'adresse même de la page. Le nom
/// attend dans [enAttente] que l'accueil l'ouvre, comme un partage : le lien
/// a pu lancer Rempart avant toute connexion. iOS n'est pas fait (il faut les
/// liens universels, donc le Mac) : le lien y ouvre la version web.
class LienContactEntrant {
  LienContactEntrant._();

  static final instance = LienContactEntrant._();

  final enAttente = ValueNotifier<String?>(null);

  String? _dernier;
  DateTime? _recuA;

  Future<void> init() async {
    if (estWeb) {
      _recevoir(Uri.base.toString());
      return;
    }
    if (!estAndroid) return;
    // Supabase écoute déjà ce flux (`AppLinks` est partagé) : le lien qui a
    // lancé l'application y est passé avant nous, d'où `getInitialLink`.
    final liens = AppLinks();
    liens.stringLinkStream.listen(
      _recevoir,
      onError: (Object e) => debugPrint('Lien de contact : $e'),
    );
    try {
      final lancement = await liens.getInitialLinkString();
      if (lancement != null) _recevoir(lancement);
    } catch (e) {
      debugPrint('Lien de contact : lancement illisible ($e)');
    }
  }

  void _recevoir(String lien) {
    final maintenant = DateTime.now();
    // ponytail: le lien de lancement peut arriver par les deux chemins à la
    // fois ; le même lien à moins de deux secondes est un doublon. Un vrai
    // jeton de lancement s'imposerait si l'on voyait deux fiches d'affilée.
    final recuA = _recuA;
    if (lien == _dernier &&
        recuA != null &&
        maintenant.difference(recuA) < const Duration(seconds: 2)) {
      return;
    }
    _dernier = lien;
    _recuA = maintenant;
    final nom = nomDepuisLienContact(lien);
    if (nom != null) enAttente.value = nom;
  }

  /// Retire le nom en attente et le rend.
  String? prendre() {
    final nom = enAttente.value;
    enAttente.value = null;
    return nom;
  }
}
