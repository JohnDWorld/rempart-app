import 'package:firebase_messaging/firebase_messaging.dart';

import 'notification_service.dart';

/// Traitement d'un message FCM reçu alors que l'application est fermée.
///
/// Fonction de premier niveau annotée `vm:entry-point` : Flutter la rappelle
/// dans un isolate dédié, sans passer par l'app. Elle vit dans son propre
/// fichier car cette annotation fait du fichier un point d'entrée aux yeux de
/// l'analyseur, qui juge alors « inatteignable » tout le reste de la même
/// bibliothèque.
///
/// Le push ne porte qu'un identifiant d'événement (`event_id_only`) : le texte
/// est reconstitué ici même, en remontant un client Matrix éphémère qui
/// déchiffre depuis la base locale (voir `push_contenu.dart`). Rien ne
/// traverse le réseau en clair, et si quoi que ce soit manque, la notification
/// se réduit à un avis neutre.
@pragma('vm:entry-point')
Future<void> traiterMessageFcmEnArrierePlan(RemoteMessage message) async {
  await NotificationService.instance.init(demanderAutorisation: false);
  await NotificationService.instance.notifierPush(
    roomId: message.data['room_id'] as String?,
    eventId: message.data['event_id'] as String?,
  );
}
