import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../../core/plateforme.dart';
import '../../core/utils/apercu_notification.dart';
import '../models/matrix_extensions.dart';
import '../providers/contenu_notifications.dart';
import 'presence_isolate.dart';
import 'push_contenu.dart';

/// Notifications locales des nouveaux messages Matrix.
///
/// S'abonne à `client.onNotification`, le flux que le SDK alimente déjà en
/// appliquant les *push rules* du serveur (messages des autres, room non
/// silencieuse, invitations). On ne re-décide donc pas ici de ce qui mérite une
/// notification.
///
/// Portée : tant que le processus de l'app vit (premier plan ou récent en
/// arrière-plan). Une notification quand l'app est tuée demande une chaîne push
/// serveur (pusher Matrix + passerelle), ce que ceci ne remplace pas.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const _canalId = 'messages';
  static const _canalNom = 'Messages';

  final _plugin = FlutterLocalNotificationsPlugin();

  StreamSubscription<matrix.Event>? _abonnement;
  bool _pret = false;

  String? _roomOuverte;

  /// Conversation actuellement ouverte : on ne notifie pas ce que
  /// l'utilisateur est déjà en train de lire.
  String? get roomOuverte => _roomOuverte;

  /// Poser une conversation efface aussi sa notification en attente.
  ///
  /// Empêcher les nouvelles ne suffisait pas : celle qui avait fait ouvrir
  /// l'application restait dans le bandeau une fois le message lu, et il
  /// fallait la balayer à la main. C'est ici que ça se règle plutôt qu'à
  /// l'appel, pour que tout chemin qui ouvre une conversation en profite.
  set roomOuverte(String? roomId) {
    _roomOuverte = roomId;
    if (roomId != null) unawaited(effacerNotification(roomId));
  }

  /// Retire la notification d'une conversation, si elle est encore affichée.
  ///
  /// L'identifiant est celui de la room, comme à l'affichage : les deux formes
  /// de notification (avec ou sans contenu) le partagent, un seul retrait
  /// suffit donc.
  Future<void> effacerNotification(String roomId) async {
    try {
      // Le plugin n'est pas forcément initialisé : au premier lancement,
      // l'écran de conversation peut s'ouvrir avant lui, et le retrait
      // échouerait en silence. Jamais de demande d'autorisation ici, la
      // méthode est appelée depuis des chemins qui n'attendent rien.
      await init(demanderAutorisation: false);
      await _plugin.cancel(id: roomId.hashCode);
    } catch (e) {
      // Le plugin n'est pas initialisé, ou la notification n'existe plus :
      // rien de tout cela ne mérite de remonter à l'utilisateur.
      debugPrint('NotificationService: notification non retirée ($e)');
    }
  }

  /// Appelé quand l'utilisateur touche une notification.
  void Function(String roomId)? onOuvrirRoom;

  /// Prépare le plugin de notifications.
  ///
  /// [demanderAutorisation] doit rester faux hors interface : dans un isolate
  /// d'arrière-plan (réveil par push, application fermée), il n'existe aucune
  /// Activity à qui présenter la demande, et l'appel échoue en
  /// NullPointerException côté Android. Le canal, lui, se crée sans interface.
  Future<void> init({bool demanderAutorisation = true}) async {
    if (_pret) return;
    // Le web n'a pas de notifications locales : le greffon n'y a aucune
    // implémentation et le moindre appel lève. Un navigateur sait notifier,
    // mais par une autre API, et ce n'est pas le sujet de cette version.
    if (estWeb) {
      _pret = true;
      return;
    }

    const parametres = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(
      settings: parametres,
      onDidReceiveNotificationResponse: (reponse) {
        final roomId = reponse.payload;
        if (roomId != null && roomId.isNotEmpty) {
          onOuvrirRoom?.call(roomId);
        }
      },
    );

    if (estAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      // Le canal doit exister avant la première notification (Android 8+).
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _canalId,
          _canalNom,
          description: 'Nouveaux messages reçus',
          importance: Importance.high,
        ),
      );
      // Android 13+ : l'autorisation se demande explicitement, et seulement
      // depuis l'interface (voir [demanderAutorisation]).
      if (demanderAutorisation) {
        await android?.requestNotificationsPermission();
      }
    }

    _pret = true;
  }

  /// Le système autorise-t-il l'affichage de notifications ?
  ///
  /// Question préalable à toute voie de push : sans cette autorisation, le
  /// serveur réveillerait l'application pour une notification qu'Android
  /// jetterait aussitôt. L'utilisateur ne verrait rien et croirait à une panne
  /// de réseau.
  Future<bool> autorisationAccordee() async {
    if (!estAndroid) return true;
    await init(demanderAutorisation: false);
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.areNotificationsEnabled() ?? true;
  }

  /// Branche les notifications sur un client Matrix connecté.
  Future<void> ecouter(matrix.Client client) async {
    await init();
    await _abonnement?.cancel();
    _abonnement = client.onNotification.stream.listen(_notifier);
  }

  Future<void> arreter() async {
    await _abonnement?.cancel();
    _abonnement = null;
    await _plugin.cancelAll();
  }

  /// Notification déclenchée par un push, application éventuellement fermée.
  ///
  /// La charge utile ne porte qu'un identifiant d'événement (`event_id_only`),
  /// et le serveur ne pourrait de toute façon rien dire d'un message chiffré.
  /// Le texte est donc reconstitué **sur l'appareil** par [apercuDuPush], qui
  /// remonte un client Matrix éphémère et déchiffre. Si quoi que ce soit
  /// manque, on retombe sur l'avis neutre.
  ///
  /// Sans `eventId`, rien ne s'affiche : le serveur pousse aussi des mises à
  /// jour de compteur, sans le moindre événement (après un départ de room, une
  /// lecture ailleurs...). Les afficher donnait des « Nouveau message »
  /// fantômes, typiquement juste après la suppression d'un groupe.
  Future<void> notifierPush({String? roomId, String? eventId}) async {
    // Appelée aussi bien depuis l'app que depuis un isolate d'arrière-plan :
    // ne jamais y demander d'autorisation.
    await init(demanderAutorisation: false);
    if (eventId == null) return;
    if (roomId != null && roomId == roomOuverte) return;

    // Application vivante : sa boucle de sync livre déjà l'événement déchiffré
    // à `_notifier`, qui notifiera mieux et plus vite. Surtout, poursuivre
    // ouvrirait un **second client Matrix sur la même base**, dont le verrou
    // SQLite est déjà tenu : les deux se le disputent, et au retour dans
    // l'application la synchronisation tombe en erreur, sans plus rien
    // afficher que « hors ligne ».
    //
    // Le test porte sur le processus et non sur ce singleton : dans l'isolate
    // d'arrière-plan, celui-ci vient de naître et se croit toujours
    // déconnecté. C'est précisément ce qui rendait ce garde inopérant quand
    // l'application était en arrière-plan mais vivante, le cas le plus courant
    // puisqu'il suffit d'attendre une réponse en faisant autre chose.
    if (PresenceIsolate.applicationVivante) return;

    // Le réglage est relu ici, et non pris sur le champ `afficherContenu` :
    // dans l'isolate d'arrière-plan, ce singleton vient de naître avec sa
    // valeur par défaut (vrai), et `main.dart` n'y a jamais posé le choix de
    // l'utilisateur. S'y fier montrerait le contenu à quelqu'un qui n'en veut
    // pas, précisément sur l'écran verrouillé.
    if (!await chargerContenuNotifications()) {
      await _afficherNeutre(roomId);
      return;
    }

    final apercu =
        roomId == null ? null : await apercuDuPush(roomId: roomId, eventId: eventId);
    if (apercu == null || roomId == null) {
      await _afficherNeutre(roomId);
      return;
    }
    await _afficher(id: roomId.hashCode, apercu: apercu, roomId: roomId);
  }

  /// Affiche une notification de message.
  ///
  /// L'identifiant est celui de la room : un nouveau message y remplace le
  /// précédent au lieu d'empiler une notification par message.
  Future<void> _afficher({
    required int id,
    required ApercuNotification apercu,
    required String roomId,
  }) async {
    await _plugin.show(
      id: id,
      title: apercu.titre,
      body: apercu.corps,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _canalId,
          _canalNom,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: roomId,
    );
  }

  /// Avis sans expéditeur ni texte, affiché quand on n'a rien à dire (réveil
  /// par push) ou quand l'utilisateur ne veut rien voir (réglage).
  Future<void> _afficherNeutre(String? roomId) async {
    await _plugin.show(
      id: (roomId ?? 'rempart').hashCode,
      title: 'Rempart',
      body: 'Nouveau message',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _canalId,
          _canalNom,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: roomId,
    );
  }

  /// L'utilisateur accepte-t-il de voir ses messages dans les notifications ?
  ///
  /// Posé par `main.dart` au démarrage et par l'écran des réglages. Le service
  /// vit hors de Riverpod (il est appelé depuis la boucle de sync et depuis un
  /// isolate), d'où ce simple champ plutôt qu'une lecture de provider.
  bool afficherContenu = true;

  Future<void> _notifier(matrix.Event event) async {
    try {
      final room = event.room;
      // Rien à signaler pour la conversation déjà à l'écran.
      if (room.id == roomOuverte) return;

      // Une réaction : à annoncer, mais seulement si elle vise un de nos
      // propres messages. Dans un groupe, relayer toutes celles que les
      // autres s'échangent ferait un vacarme dont personne ne veut.
      final symbole = event.symboleReaction;
      if (symbole != null) {
        final cible = event.cibleReaction;
        if (cible == null) return;
        final vise = await room.getEventById(cible);
        if (vise == null || vise.senderId != room.client.userID) return;
        if (!afficherContenu) {
          await _afficherNeutre(room.id);
          return;
        }
        await _afficher(
          id: room.id.hashCode,
          apercu: composerApercu(
            texte: 'a réagi $symbole à votre message',
            nomExpediteur: event.nomLisibleDeLExpediteur,
            nomRoom: room.name.isEmpty ? null : room.name,
          ),
          roomId: room.id,
        );
        return;
      }

      if (!afficherContenu) {
        await _afficherNeutre(room.id);
        return;
      }

      final apercu = composerApercu(
        texte: await _corps(event),
        nomExpediteur: event.nomLisibleDeLExpediteur,
        nomRoom: room.name.isEmpty ? null : room.name,
      );

      await _afficher(id: room.id.hashCode, apercu: apercu, roomId: room.id);
    } catch (e) {
      // Une notification ratée ne doit jamais casser la boucle de sync.
      debugPrint('NotificationService: notification ignorée ($e)');
    }
  }

  /// Texte du message, déchiffré si besoin.
  Future<String> _corps(matrix.Event event) async {
    if (event.type == matrix.EventTypes.RoomMember) {
      return 'Vous avez été invité à une conversation';
    }

    var evenement = event;
    if (evenement.type == matrix.EventTypes.Encrypted) {
      // L'événement arrive chiffré : sans déchiffrement, le corps est vide.
      final chiffrement = event.room.client.encryption;
      if (chiffrement != null) {
        evenement = await chiffrement.decryptRoomEvent(evenement);
      }
    }

    final texte = evenement.plaintextBody.trim();
    return texte.isEmpty ? 'Nouveau message' : texte;
  }
}
