import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Envoi des rapports de plantage vers GlitchTip, instance auto-hébergée.
///
/// GlitchTip parle le protocole Sentry, d'où le SDK `sentry_flutter` pointé sur
/// notre propre serveur : aucun rapport ne part chez un tiers.
///
/// Un rapport porte une pile d'appels et le modèle de l'appareil, **jamais** un
/// contenu de message : promettre le chiffrement de bout en bout et laisser
/// fuir un extrait de conversation dans un rapport d'erreur serait la pire des
/// contradictions. Les réglages ci-dessous verrouillent ça explicitement plutôt
/// que de s'en remettre aux valeurs par défaut du SDK.
Future<void> lancerAvecRapportsDePlantage(
  FutureOr<void> Function() demarrer,
) async {
  final dsn = dotenv.env['SENTRY_DSN']?.trim() ?? '';

  // Sans DSN, rien n'est initialisé : ni collecte, ni requête réseau. C'est le
  // cas d'un poste de développement qui n'a pas de serveur en face, et c'est
  // aussi ce qui permet de construire une variante sans télémétrie du tout.
  if (dsn.isEmpty) {
    debugPrint('Plantages : aucun SENTRY_DSN, collecte désactivée');
    await demarrer();
    return;
  }

  await SentryFlutter.init(
    (options) {
      options
        ..dsn = dsn
        ..environment = kReleaseMode ? 'release' : 'debug'
        // Rien qui identifie la personne : ni adresse IP, ni identifiant de
        // session, ni en-têtes de requête.
        ..sendDefaultPii = false
        // Une capture d'écran au moment du plantage montrerait la
        // conversation ouverte. Hors de question. (L'arbre de widgets, qui
        // poserait le même problème, reste désactivé par défaut ; l'option
        // correspondante est encore expérimentale côté SDK.)
        ..attachScreenshot = false
        // Les fils d'Ariane automatiques enregistrent les frappes et les
        // navigations : trop bavard pour une messagerie, et sans valeur pour
        // diagnostiquer un plantage.
        ..enableUserInteractionBreadcrumbs = false
        ..enableAutoNativeBreadcrumbs = false
        // Aucune mesure de performance : on ne veut que les plantages, et
        // chaque transaction serait un aller-retour réseau de plus.
        ..tracesSampleRate = 0.0
        ..beforeSend = _retirerLesTracesPersonnelles;
    },
    appRunner: demarrer,
  );
}

/// Dernier filet avant l'envoi : on jette ce qui pourrait porter du texte
/// d'utilisateur, quelle qu'en soit l'origine.
///
/// Le SDK n'est pas censé remplir ces champs avec nos réglages, mais un
/// paquet tiers peut poser un fil d'Ariane, et une future mise à jour changer
/// un défaut. La règle est appliquée ici une fois pour toutes, au dernier
/// moment, plutôt que d'être supposée acquise.
SentryEvent? _retirerLesTracesPersonnelles(SentryEvent event, Hint hint) {
  return event
    ..breadcrumbs = const []
    ..user = null
    ..request = null;
}
