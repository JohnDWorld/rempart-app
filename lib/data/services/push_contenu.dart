import 'package:flutter/foundation.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as flutter_vod;
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

import '../../core/constants/matrix_constants.dart';
import '../../core/utils/apercu_notification.dart';
import '../models/matrix_extensions.dart';

/// Va chercher le contenu réel d'un message annoncé par un push.
///
/// Le push ne transporte qu'un identifiant d'événement : le pusher est déclaré
/// en `event_id_only`, et de toute façon le serveur ne peut rien dire d'un
/// message chiffré, dont il n'a pas les clés. Le texte n'existe donc nulle part
/// ailleurs que sur cet appareil, et c'est ici qu'on le reconstitue.
///
/// Appelée depuis l'isolate d'arrière-plan, sans application vivante autour :
/// tout ce dont le SDK a besoin (vodozemac, la base locale, le client) est
/// remonté puis refermé le temps d'un message.
///
/// Rend `null` dès que quoi que ce soit manque, et c'est le cas normal, pas
/// l'exception : session Megolm absente, base verrouillée par l'application au
/// premier plan, serveur injoignable, message déjà lu. L'appelant retombe alors
/// sur l'avis neutre, qui reste une notification correcte.
Future<ApercuNotification?> apercuDuPush({
  required String roomId,
  required String eventId,
}) {
  // Ceinture de sécurité : quoi qu'il arrive, cet isolate lâche la base au
  // bout de quinze secondes. Le garde d'appel doit déjà l'empêcher d'ouvrir
  // une base tenue par l'application, mais si jamais il échouait, une attente
  // sans fin sur un verrou SQLite immobiliserait les deux côtés. Mieux vaut
  // une notification sans contenu qu'une application figée.
  return _apercuDuPush(roomId: roomId, eventId: eventId)
      .timeout(const Duration(seconds: 15), onTimeout: () => null);
}

Future<ApercuNotification?> _apercuDuPush({
  required String roomId,
  required String eventId,
}) async {
  Client? client;
  try {
    // vodozemac AVANT le client : sans lui, `Client.init` laisse le module de
    // chiffrement à null et l'événement revient illisible.
    if (!vod.isInitialized()) {
      await flutter_vod.init();
    }

    final dossier = await getApplicationDocumentsDirectory();
    final base = await openDatabase(
      '${dossier.path}/${MatrixConstants.applicationName}.db',
    );
    client = Client(
      MatrixConstants.applicationName,
      database: await MatrixSdkDatabase.init(
        MatrixConstants.applicationName,
        database: base,
      ),
    );

    // Le strict nécessaire : ni premier `/sync` attendu, ni chargement complet
    // des rooms. On ne veut qu'une chose, et l'utilisateur attend sa
    // notification maintenant.
    await client.init(
      waitForFirstSync: false,
      waitUntilLoadCompletedLoaded: false,
    );
    if (!client.isLogged()) return null;

    final evenement = await client.getEventByPushNotification(
      PushNotification(roomId: roomId, eventId: eventId),
      // Ne rien écrire depuis cet isolate : l'application au premier plan peut
      // tenir la même base, et une écriture concurrente est le seul moyen
      // d'abîmer quelque chose ici. La synchronisation normale rattrapera.
      storeInDatabase: false,
    );
    // null = message déjà lu ailleurs, ou introuvable. Ne pas notifier du tout
    // serait le bon geste, mais l'appelant a déjà décidé qu'il notifiait :
    // il retombera sur l'avis neutre.
    if (evenement == null) return null;

    // Une réaction n'est pas un message, mais elle mérite d'être annoncée : on
    // répond à un agent par un ✅, et savoir qu'il a été vu compte.
    final symbole = evenement.symboleReaction;
    if (symbole != null) {
      final cible = evenement.cibleReaction;
      if (cible == null) return null;
      // Ne notifier que les réactions à SES PROPRES messages : dans un groupe,
      // annoncer toutes celles qui s'échangent entre les autres ferait un
      // vacarme dont personne ne veut. En cas de doute (cible introuvable,
      // réseau absent), on se tait plutôt que de déranger pour rien.
      final vise = await evenement.room.getEventById(cible);
      if (vise == null || vise.senderId != client.userID) return null;
      return composerApercu(
        texte: 'a réagi $symbole à votre message',
        nomExpediteur: evenement.nomLisibleDeLExpediteur,
        nomRoom: evenement.room.name.isEmpty ? null : evenement.room.name,
      );
    }

    if (evenement.type != EventTypes.Message) return null;
    // Le déchiffrement a échoué : afficher « Message chiffré » serait pire que
    // « Nouveau message », qui au moins ne parle pas d'un échec.
    if (evenement.messageType == MessageTypes.BadEncrypted) return null;

    // `texteApercu` et non le corps brut : le corps d'une pièce jointe est son
    // nom de fichier, et la notification annonçait « vocal_1788… .m4a ». Il
    // masque aussi les secrets, ce qu'une notification doit faire plus encore
    // qu'un écran déverrouillé.
    final texte = evenement.texteApercu.trim();
    if (texte.isEmpty) return null;

    return composerApercu(
      texte: texte,
      nomExpediteur: evenement.nomLisibleDeLExpediteur,
      nomRoom: evenement.room.name.isEmpty ? null : evenement.room.name,
    );
  } catch (e) {
    // Base verrouillée, serveur absent, clés manquantes : rien de tout cela ne
    // doit empêcher la notification neutre de partir.
    debugPrint('Push: contenu indisponible ($e)');
    return null;
  } finally {
    await client?.dispose();
  }
}
