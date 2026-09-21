import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unifiedpush/unifiedpush.dart';

import '../../core/constants/push_constants.dart';
import '../../core/plateforme.dart';
import 'matrix_service.dart';
import 'notification_service.dart';
import 'push_background.dart';

/// Voie effectivement utilisée pour réveiller l'app.
///
/// [refuse] se distingue de [aucun] : il ne s'agit pas d'un appareil sans
/// moyen de push, mais d'une autorisation système absente. Le remède n'est pas
/// le même, donc l'état non plus.
enum TransportPush { fcm, unifiedpush, aucun, refuse }

/// Notifications lorsque l'application est fermée, par deux voies au choix.
///
/// - **FCM** (variante grand public) : Google Play Services garde une unique
///   connexion pour tout le téléphone et réveille l'app, comme le font les
///   autres messageries. Sobre en batterie et fiable, mais Google observe
///   qu'une notification vous est destinée.
/// - **UnifiedPush** (variante souveraine) : tout passe par le serveur Rempart,
///   au prix d'une application distributeur (ntfy) à installer.
///
/// Les deux transmettent un simple réveil : le pusher est déclaré en
/// `event_id_only`, donc la notification poussée ne porte ni expéditeur ni
/// texte. Aucun contenu ne traverse la chaîne, quelle que soit la voie.
///
/// Le choix est piloté par `PUSH_MODE` dans le `.env`, et surchargeable par
/// l'utilisateur dans les réglages.
class PushService {
  PushService._();

  static final PushService instance = PushService._();

  /// Nom d'instance UnifiedPush (une seule ici : le compte courant).
  static const _instanceUp = 'rempart';

  /// Identifiants de pusher côté Matrix, distincts par voie : c'est ainsi que
  /// le serveur sait quelle passerelle appeler, et qu'il remplace le bon
  /// enregistrement au lieu d'en empiler un par redémarrage.
  static const _appIdUp = 'fr.rempart.messenger.up';
  static const _appIdFcm = 'fr.rempart.messenger.fcm';

  /// Clé du choix utilisateur, prioritaire sur le `.env`.
  static const _cleMode = 'push_mode';

  /// Préfixe de stockage des pushkeys déclarées, par `app_id`.
  static const _clePushkey = 'push_key_';

  bool _pret = false;

  /// UnifiedPush n'existe que sur Android : le greffon ne fournit aucune
  /// implémentation iOS et lève `UnimplementedError` au premier appel. On
  /// retient ici s'il a pu être branché, pour ne plus le solliciter ensuite.
  bool _unifiedPushDispo = false;

  TransportPush _transport = TransportPush.aucun;

  /// Voie active depuis le dernier démarrage (pour l'affichage des réglages).
  TransportPush get transport => _transport;

  /// Mode retenu : choix de l'utilisateur s'il en a fait un, sinon celui du
  /// build.
  Future<ModePush> modeActif() async {
    final prefs = await SharedPreferences.getInstance();
    final choisi = prefs.getString(_cleMode);
    return choisi == null
        ? PushConstants.modeParDefaut
        : ModePush.depuis(choisi);
  }

  /// Enregistre le choix de l'utilisateur et réapplique la configuration.
  Future<TransportPush> choisirMode(ModePush mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cleMode, mode.name);
    await arreter();
    return demarrer();
  }

  /// Branche les rappels UnifiedPush. À appeler au démarrage, y compris quand
  /// l'app est réveillée en arrière-plan pour une notification.
  Future<void> init() async {
    if (_pret) return;
    _pret = true;
    // UnifiedPush et FCM supposent un appareil : dans un navigateur, l'onglet
    // ouvert tient la synchronisation, et rien ne réveille une page fermée.
    if (estWeb) return;

    // Sans ce garde-fou, l'exception remontait jusqu'à `demarrer()`, qui
    // commence par `await init()` : sur iOS la mise en place du push s'arrêtait
    // donc là, et la voie FCM - pourtant la bonne sur cette plateforme -
    // n'était jamais tentée.
    try {
      await UnifiedPush.initialize(
        onNewEndpoint: _onNouveauEndpoint,
        onMessage: _onMessageUp,
        onRegistrationFailed: (raison, _) => debugPrint(
            'Push: enregistrement refusé par le distributeur ($raison)'),
        onUnregistered: (_) =>
            debugPrint('Push: désinscrit par le distributeur'),
        onTempUnavailable: (_) =>
            debugPrint('Push: distributeur temporairement indisponible'),
      );
      _unifiedPushDispo = true;
    } catch (e) {
      debugPrint('Push: UnifiedPush indisponible sur cette plateforme ($e)');
      _unifiedPushDispo = false;
    }
  }

  /// Met en place la voie de push la mieux adaptée et renvoie celle retenue.
  ///
  /// `TransportPush.aucun` n'est pas une erreur : c'est le cas d'un utilisateur
  /// sans Google ni distributeur, pour lequel l'app se rabat sur sa propre
  /// connexion (voir `SyncArrierePlanService`).
  Future<TransportPush> demarrer() async {
    if (estWeb) return _transport = TransportPush.aucun;
    await init();
    final mode = await modeActif();

    if (mode == ModePush.aucun) {
      await _supprimerPusher(_appIdFcm);
      await _supprimerPusher(_appIdUp);
      return _transport = TransportPush.aucun;
    }

    // Autorisation système d'abord : sans elle aucune voie n'aboutit, et la
    // cascade se contenterait de basculer d'un transport muet à un autre.
    // Basculer en douce masquait la vraie cause (FCM refusé -> repli sur
    // UnifiedPush -> toujours rien à l'écran).
    if (!await NotificationService.instance.autorisationAccordee()) {
      debugPrint('Push: notifications refusées au niveau système');
      await _supprimerPusher(_appIdFcm);
      await _supprimerPusher(_appIdUp);
      return _transport = TransportPush.refuse;
    }

    if (mode == ModePush.fcm || mode == ModePush.auto) {
      if (await _demarrerFcm()) {
        await _supprimerPusher(_appIdUp);
        return _transport = TransportPush.fcm;
      }
      // Mode FCM explicite : ne pas basculer en douce sur l'autre voie, qui
      // n'a pas les mêmes implications de confidentialité.
      if (mode == ModePush.fcm) {
        return _transport = TransportPush.aucun;
      }
    }

    if (mode == ModePush.unifiedpush || mode == ModePush.auto) {
      if (await _demarrerUnifiedPush()) {
        await _supprimerPusher(_appIdFcm);
        return _transport = TransportPush.unifiedpush;
      }
    }

    // Plus aucune voie active : ne laisser aucun pusher derrière soi, sinon le
    // serveur continuerait de pousser vers un transport qu'on n'écoute plus.
    await _supprimerPusher(_appIdFcm);
    await _supprimerPusher(_appIdUp);
    return _transport = TransportPush.aucun;
  }

  /// Coupe le push : à la déconnexion, pour ne pas continuer à réveiller
  /// l'appareil pour un compte qui n'est plus le sien.
  Future<void> arreter() async {
    _transport = TransportPush.aucun;
    try {
      await UnifiedPush.unregister(_instanceUp);
    } catch (e) {
      debugPrint('Push: désinscription UnifiedPush impossible ($e)');
    }
  }

  // --- FCM -----------------------------------------------------------------

  /// Initialisation de Firebase, faite une fois pour toutes.
  ///
  /// Deux pièges se cumulaient ici, et leur effet était invisible : le pusher
  /// se déclarait bien côté serveur, mais l'application n'enregistrait jamais
  /// son gestionnaire d'arrière-plan. Le serveur poussait donc dans le vide, et
  /// aucune notification n'arrivait, application fermée.
  ///
  /// 1. `firebase_core` crée parfois l'app par défaut **côté natif** avant que
  ///    `Firebase.apps` ne la voie côté Dart : le garde `apps.isEmpty` laissait
  ///    alors passer un second `initializeApp`, qui échouait sur
  ///    « FirebaseApp name [DEFAULT] already exists! ».
  /// 2. Deux chemins (`_demarrerFcm` et la relecture du jeton) initialisaient
  ///    en parallèle, chacun voyant une liste vide : la course produisait la
  ///    même erreur.
  ///
  /// Le Future est donc mémorisé (un seul appel, quels que soient les
  /// appelants), et une app déjà présente vaut succès plutôt qu'échec.
  Future<bool>? _firebasePret;

  Future<bool> _assurerFirebase() {
    final options = PushConstants.optionsFirebase;
    if (options == null) return Future.value(false);
    return _firebasePret ??= () async {
      try {
        await Firebase.initializeApp(options: options);
        return true;
      } catch (e) {
        if (Firebase.apps.isNotEmpty) return true;
        debugPrint('Push: Firebase indisponible ($e)');
        return false;
      }
    }();
  }

  /// Jeton FCM de cet appareil, ou null si FCM n'est pas utilisable ici.
  Future<String?> _jetonFcmCourant() async {
    if (!await _assurerFirebase()) return null;
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('Push: jeton FCM indisponible ($e)');
      return null;
    }
  }

  Future<bool> _demarrerFcm() async {
    // Options fournies explicitement : pas de google-services.json, donc la
    // variante souveraine se construit sans le moindre fichier Google.
    if (!await _assurerFirebase()) {
      debugPrint('Push: FCM non configuré dans ce build');
      return false;
    }

    try {
      final messagerie = FirebaseMessaging.instance;
      final autorisation = await messagerie.requestPermission();
      if (autorisation.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint("Push: notifications refusées par l'utilisateur");
        return false;
      }

      final jeton = await messagerie.getToken();
      if (jeton == null) {
        debugPrint('Push: aucun jeton FCM (Play Services absent ?)');
        return false;
      }

      FirebaseMessaging.onBackgroundMessage(traiterMessageFcmEnArrierePlan);
      FirebaseMessaging.onMessage.listen((message) {
        unawaited(NotificationService.instance.notifierPush(
          roomId: message.data['room_id'] as String?,
          eventId: message.data['event_id'] as String?,
        ));
      });
      // Le jeton peut tourner sans intervention : le pusher doit suivre.
      messagerie.onTokenRefresh.listen(
        (nouveau) => unawaited(_declarerPusher(
          pushkey: nouveau,
          appId: _appIdFcm,
          gatewayUrl: PushConstants.fcmGatewayUrl,
        )),
      );

      await _declarerPusher(
        pushkey: jeton,
        appId: _appIdFcm,
        gatewayUrl: PushConstants.fcmGatewayUrl,
      );
      return true;
    } catch (e) {
      // Absence de Play Services, projet Firebase invalide, appareil
      // dégooglisé : autant de cas normaux, pas des pannes.
      debugPrint('Push: FCM indisponible ($e)');
      return false;
    }
  }

  // --- UnifiedPush ---------------------------------------------------------

  Future<bool> _demarrerUnifiedPush() async {
    if (!_unifiedPushDispo) return false;

    final distributeur = await UnifiedPush.tryUseCurrentOrDefaultDistributor();
    if (!distributeur) {
      debugPrint('Push: aucun distributeur UnifiedPush installé');
      return false;
    }
    await UnifiedPush.register(instance: _instanceUp);
    return true;
  }

  Future<void> _onNouveauEndpoint(PushEndpoint endpoint, String instance) =>
      _declarerPusher(
        pushkey: endpoint.url,
        appId: _appIdUp,
        gatewayUrl: PushConstants.gatewayUrl,
      );

  /// Notification poussée reçue du distributeur UnifiedPush.
  Future<void> _onMessageUp(PushMessage message, String instance) async {
    try {
      final json =
          jsonDecode(utf8.decode(message.content)) as Map<String, dynamic>;
      final notification = json['notification'] as Map<String, dynamic>?;
      await NotificationService.instance.notifierPush(
        roomId: notification?['room_id'] as String?,
        eventId: notification?['event_id'] as String?,
      );
    } catch (e) {
      debugPrint('Push: message illisible ($e)');
      // Charge illisible : on prévient quand même, un vrai message se cache
      // peut-être derrière. Le faux identifiant ne sert qu'à passer le
      // garde-fou anti-fantôme, qui vise les pushes de compteur bien formés.
      await NotificationService.instance.notifierPush(eventId: 'inconnu');
    }
  }

  // --- Commun --------------------------------------------------------------

  /// Déclare le pusher à Synapse : c'est lui qui contactera la passerelle.
  Future<void> _declarerPusher({
    required String pushkey,
    required String appId,
    required String gatewayUrl,
  }) async {
    final client = MatrixService.instance.client;
    if (client == null || !client.isLogged()) {
      debugPrint('Push: pusher non déclaré (session Matrix absente)');
      return;
    }

    try {
      await client.postPusher(
        matrix.Pusher(
          appId: appId,
          pushkey: pushkey,
          appDisplayName: 'Rempart',
          deviceDisplayName: client.deviceName ?? 'Appareil',
          // Signature de l'appareil : les pushers sont rattachés au compte, pas
          // à l'appareil, et rien d'autre ne permet de reconnaître les siens.
          // Sans elle, faire le ménage reviendrait à supprimer aussi ceux des
          // autres appareils du même compte.
          profileTag: client.deviceID,
          kind: 'http',
          lang: 'fr',
          data: matrix.PusherData(
            url: Uri.parse(gatewayUrl),
            // `event_id_only` : la notification poussée ne transporte ni
            // expéditeur ni texte, seulement de quoi identifier l'événement.
            format: 'event_id_only',
          ),
        ),
        // Remplace l'enregistrement précédent de cet appareil pour cette voie.
        append: false,
      );
      // Mémoriser la clé : c'est le seul moyen de retrouver ce pusher pour le
      // supprimer plus tard, l'API Matrix ne permettant pas de lister les
      // pushers d'un appareil donné.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_clePushkey$appId', pushkey);
      debugPrint('Push: pusher $appId déclaré');
    } catch (e) {
      debugPrint('Push: déclaration du pusher échouée ($e)');
    }
  }

  /// Supprime les pushers de cet appareil pour une voie devenue inactive.
  ///
  /// Indispensable au basculement : les deux voies ont des `app_id` distincts
  /// (pour que Synapse appelle la bonne passerelle), donc déclarer l'une
  /// n'écrase pas l'autre. Sans cette suppression, le serveur pousserait par
  /// les deux et chaque message arriverait EN DOUBLE.
  ///
  /// On interroge le serveur au lieu de se fier à une clé mémorisée en local.
  /// L'ancienne version supprimait la clé mémorisée dès que l'appel réseau
  /// répondait, y compris quand le serveur n'avait rien supprimé : le pusher
  /// devenait alors introuvable et survivait indéfiniment.
  ///
  /// Seuls les pushers portant l'identifiant de CET appareil sont retirés :
  /// deux appareils d'un même compte peuvent légitimement emprunter des voies
  /// différentes (un téléphone en UnifiedPush, un autre en FCM), et se
  /// supprimer mutuellement les ferait basculer sans fin.
  Future<void> _supprimerPusher(String appId) async {
    final client = MatrixService.instance.client;
    if (client == null || !client.isLogged()) return;

    final prefs = await SharedPreferences.getInstance();
    // Clés reconnues comme miennes, pour les pushers antérieurs à la signature
    // par appareil : la dernière déclarée, et le jeton FCM courant.
    final clesConnues = <String>{};
    final memorisee = prefs.getString('$_clePushkey$appId');
    if (memorisee != null) clesConnues.add(memorisee);
    if (appId == _appIdFcm) {
      final jeton = await _jetonFcmCourant();
      if (jeton != null) clesConnues.add(jeton);
    }

    try {
      final pushers = await client.getPushers() ?? const <matrix.Pusher>[];
      final miens = pushers.where(
        (p) =>
            p.appId == appId &&
            (p.profileTag == client.deviceID ||
                clesConnues.contains(p.pushkey)),
      );

      for (final pusher in miens) {
        await client.deletePusher(
          matrix.PusherId(appId: pusher.appId, pushkey: pusher.pushkey),
        );
        debugPrint('Push: pusher $appId supprimé');
      }

      // N'oublier la clé qu'une fois le serveur d'accord : c'est le seul moyen
      // de retenter au prochain démarrage si la suppression a échoué.
      final restants = await client.getPushers() ?? const <matrix.Pusher>[];
      final survivant = restants.any(
        (p) => p.appId == appId && clesConnues.contains(p.pushkey),
      );
      if (!survivant) {
        await prefs.remove('$_clePushkey$appId');
      } else {
        debugPrint('Push: pusher $appId toujours présent côté serveur');
      }
    } catch (e) {
      // Hors ligne ou serveur indisponible : sans gravité, la clé mémorisée
      // reste en place et la prochaine bascule réessaiera.
      debugPrint('Push: suppression du pusher $appId impossible ($e)');
    }
  }
}
