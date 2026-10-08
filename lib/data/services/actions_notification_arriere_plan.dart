import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'actions_notification.dart';
import 'notification_service.dart';
import 'presence_isolate.dart';

/// Un bouton « Répondre » ou « Marquer comme lu », sur le téléphone ou dans
/// Android Auto.
///
/// Le greffon appelle ceci dans un isolate à part, application ouverte ou
/// non : un bouton qui n'ouvre aucun écran ne passe jamais par l'isolate
/// principal. Fichier à part, comme `push_background.dart`, à cause de
/// l'annotation `vm:entry-point`.
@pragma('vm:entry-point')
Future<void> traiterActionDeNotification(NotificationResponse reponse) async {
  DartPluginRegistrant.ensureInitialized();
  final roomId = reponse.payload;
  final action = reponse.actionId;
  if (roomId == null || roomId.isEmpty || action == null) return;

  // L'application tourne : c'est son client qui agit. En ouvrir un second sur
  // la même base ferait se disputer le verrou (voir `PresenceIsolate`).
  if (PresenceIsolate.relayer(
    {'action': action, 'roomId': roomId, 'texte': reponse.input},
  )) {
    return;
  }

  final service = NotificationService.instance;
  await service.init(demanderAutorisation: false);
  final reussi = await executerActionSansApplication(
    action: action,
    roomId: roomId,
    texte: reponse.input,
  );
  await service.apresAction(
    action: action,
    roomId: roomId,
    reussi: reussi,
    texte: reponse.input,
  );
}
