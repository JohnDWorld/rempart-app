import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import 'push_contenu.dart';

/// Les deux boutons d'une notification de message. Android Auto exige les
/// deux pour afficher une messagerie dans la voiture (réponse dictée, lecture
/// à voix haute), et ils servent aussi sur le téléphone.
const actionRepondre = 'repondre';
const actionLu = 'lu';

/// Répond dans [roomId], ou marque la conversation comme lue, avec [client].
///
/// Rend faux si la réponse n'est pas partie, pour que l'appelant le dise : une
/// réponse dictée en voiture qui se perd sans un mot laisserait l'autre sans
/// nouvelles. Répondre marque aussi comme lu : on a lu ce à quoi l'on répond.
Future<bool> executerActionNotification(
  Client client, {
  required String action,
  required String roomId,
  String? texte,
}) async {
  final room = client.getRoomById(roomId);
  if (room == null) return false;
  String? dernier;
  if (action == actionRepondre) {
    final reponse = texte?.trim() ?? '';
    if (reponse.isEmpty) return true;
    // Comme partout : « /ping » part tel quel vers un bot.
    dernier = await room.sendTextEvent(reponse, parseCommands: false);
    if (dernier == null) return false;
  } else {
    // Le dernier événement selon le serveur : la base d'un client éphémère
    // peut avoir des heures de retard sur la conversation.
    final page = await client.getRoomEvents(roomId, Direction.b, limit: 1);
    dernier = page.chunk.firstOrNull?.eventId;
    if (dernier == null) return true;
  }
  try {
    await room.setReadMarker(dernier, mRead: dernier);
  } catch (e) {
    // Un accusé manqué ne doit pas faire passer une réponse partie pour perdue.
    debugPrint('Notification: accusé de lecture non posé ($e)');
  }
  return true;
}

/// La même chose application fermée, par un client éphémère.
///
/// Une seule synchronisation, sans boucle : de quoi connaître les membres et
/// les appareils actuels du salon avant de chiffrer pour eux. Bornée dans le
/// temps, et court : passé quelques dizaines de secondes, Android gèle le
/// processus réveillé pour l'occasion, et l'avis d'échec ne partirait plus.
Future<bool> executerActionSansApplication({
  required String action,
  required String roomId,
  String? texte,
}) {
  return _executerSansApplication(action, roomId, texte)
      .timeout(const Duration(seconds: 35), onTimeout: () => false);
}

Future<bool> _executerSansApplication(
  String action,
  String roomId,
  String? texte,
) async {
  Client? client;
  try {
    client = await clientEphemere()
      ..backgroundSync = false;
    await client.init();
    if (!client.isLogged()) return false;
    return await executerActionNotification(
      client,
      action: action,
      roomId: roomId,
      texte: texte,
    );
  } catch (e) {
    debugPrint('Notification: action impossible ($e)');
    return false;
  } finally {
    await client?.dispose();
  }
}
