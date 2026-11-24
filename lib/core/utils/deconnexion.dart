import 'dart:async';

import 'package:flutter/foundation.dart';

/// Ferme la session Matrix, même quand le SDK n'y arrive pas.
///
/// Le SDK commence sa déconnexion par attendre l'envoi des clés vers la
/// sauvegarde. Dans la version web, cet envoi peut rester figé pour toujours :
/// le SDK 7.4.0 lit une table d'IndexedDB avec des clés tirées de son cache,
/// et quand le cache et la base divergent (une écriture en cours), il lève
/// dans un rappel d'IndexedDB, et l'attente ne se termine jamais (corrigé en
/// 10.1.0, « read fresh keys in IndexedDB Box.getAllValues »). La déconnexion
/// restait suspendue derrière, et le bouton ne faisait plus rien.
///
/// Passé [delai], la session est fermée sans le SDK : sur le serveur, puis sur
/// l'appareil. Les données locales partent même si le serveur ne répond pas,
/// pour qu'aucune session ne reste lisible sur l'appareil.
Future<void> deconnecterSansSeBloquer({
  required Future<void> Function() deconnexionSdk,
  required Future<void> Function() fermerSurLeServeur,
  required Future<void> Function() effacerLocal,
  Duration delai = const Duration(seconds: 10),
}) async {
  try {
    await deconnexionSdk().timeout(delai);
  } on TimeoutException {
    debugPrint('Matrix : déconnexion du SDK bloquée, fermeture sans lui');
    try {
      await fermerSurLeServeur();
    } finally {
      await effacerLocal();
    }
  }
}
