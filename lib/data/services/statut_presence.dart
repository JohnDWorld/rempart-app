import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';

/// Le statut que l'utilisateur montre aux autres.
enum StatutChoisi {
  /// En ligne quand Rempart est à l'écran, absent sinon.
  automatique('Automatique', 'En ligne quand Rempart est ouvert'),
  absent('Absent', 'Toujours affiché absent'),
  invisible('Invisible', 'Vous apparaissez hors ligne');

  const StatutChoisi(this.libelle, this.description);

  final String libelle;
  final String description;
}

/// La présence à annoncer au serveur, selon le choix et l'état de l'app.
///
/// Rempart ne disait jamais qu'il passait en arrière-plan : chaque
/// synchronisation, même application quittée, marquait l'utilisateur « en
/// ligne », et Android garde l'application vivante longtemps. On voyait donc
/// quelqu'un « en ligne » alors qu'il n'avait plus Rempart sous les yeux.
matrix.PresenceType presenceAnnoncee(
  StatutChoisi choix, {
  required bool premierPlan,
}) =>
    switch (choix) {
      StatutChoisi.automatique => premierPlan
          ? matrix.PresenceType.online
          : matrix.PresenceType.unavailable,
      StatutChoisi.absent => matrix.PresenceType.unavailable,
      StatutChoisi.invisible => matrix.PresenceType.offline,
    };

/// Rempart est-il à l'écran ? Faux en arrière-plan, écran verrouillé compris.
///
/// `inactive` compte comme à l'écran : c'est l'état fugace du volet des
/// notifications tiré ou du sélecteur d'applications, et la présence ne doit
/// pas clignoter à chaque fois. Avant le premier état connu (démarrage),
/// l'application est en train de s'ouvrir.
bool get auPremierPlan => switch (WidgetsBinding.instance.lifecycleState) {
      null || AppLifecycleState.resumed || AppLifecycleState.inactive => true,
      _ => false,
    };

/// Tient la présence du compte à jour : au changement de statut, et à chaque
/// passage entre premier et arrière-plan.
class StatutPresence {
  StatutPresence._();

  static final instance = StatutPresence._();

  static const _cle = 'statut_presence';

  final choix = ValueNotifier(StatutChoisi.automatique);
  matrix.Client? _client;
  AppLifecycleListener? _ecoute;

  /// Relit le choix enregistré. Appelé au démarrage, avant la première
  /// synchronisation.
  Future<void> charger() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final nom = prefs.getString(_cle);
      choix.value = StatutChoisi.values.firstWhere(
        (s) => s.name == nom,
        orElse: () => StatutChoisi.automatique,
      );
    } catch (_) {
      // Sans préférences lisibles, le comportement par défaut.
    }
  }

  /// Branche un client connecté.
  void brancher(matrix.Client client) {
    _client = client;
    _ecoute ??= AppLifecycleListener(onStateChange: (_) => _appliquer());
    _appliquer();
  }

  Future<void> choisir(StatutChoisi nouveau) async {
    choix.value = nouveau;
    _appliquer();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cle, nouveau.name);
    } catch (_) {
      // Sans persistance, le choix vaut pour la session.
    }
  }

  void _appliquer() {
    final client = _client;
    if (client == null || !client.isLogged()) return;
    final presence = presenceAnnoncee(choix.value, premierPlan: auPremierPlan);
    // `syncPresence` accompagne chaque synchronisation : sans lui, le SDK
    // n'annonce rien, et le serveur prend toute synchronisation pour une
    // présence en ligne. `setPresence` l'applique sans attendre la suivante.
    client.syncPresence = presence;
    unawaited(
      client.setPresence(client.userID!, presence).catchError((Object e) {
        debugPrint('StatutPresence : présence non envoyée ($e)');
      }),
    );
  }
}
