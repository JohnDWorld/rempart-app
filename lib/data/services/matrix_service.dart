import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as flutter_vod;
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

import '../../core/constants/matrix_constants.dart';
import '../../core/plateforme.dart';
import '../models/matrix_extensions.dart';
import 'client_rempart.dart';
import 'notification_service.dart';

/// Service pour la gestion de la connexion et des opérations Matrix
class MatrixService {
  MatrixService._();

  static final MatrixService instance = MatrixService._();

  Client? _client;
  bool _isInitialized = false;

  /// Client Matrix (null si non initialisé)
  Client? get client => _client;

  /// Vérifie si le service est initialisé
  bool get isInitialized => _isInitialized;

  /// Vérifie si l'utilisateur est connecté
  bool get isLoggedIn => _client?.isLogged() ?? false;

  /// ID de l'utilisateur courant
  String? get currentUserId => _client?.userID;

  /// Initialisation en cours, partagée par tous les appelants.
  ///
  /// `_isInitialized` ne se pose qu'à la **fin** : deux appels rapprochés le
  /// trouvaient tous deux à faux et repartaient ensemble. Sur le web, où le
  /// WASM de vodozemac se télécharge, la fenêtre dure le temps d'un transfert,
  /// et le second appel levait « Should not initialize flutter_rust_bridge
  /// twice ». La page restait alors sur « Non connecté à Matrix » après chaque
  /// rechargement, alors que la session, elle, était bien là.
  ///
  /// Le cas se produit sans rien faire d'anormal : l'écran des conversations
  /// se reconstruit quand la fenêtre change de disposition (une colonne, puis
  /// deux), et chaque montage demande sa connexion.
  Future<void>? _initialisation;

  /// Initialise le client Matrix
  Future<void> init() {
    final encours = _initialisation;
    if (encours != null) return encours;
    final future = _init();
    _initialisation = future;
    // Un échec ne doit pas se figer : sans cela, « Réessayer » rejouerait la
    // même erreur au lieu de tenter à nouveau.
    unawaited(future.catchError((Object _) => _initialisation = null));
    return future;
  }

  Future<void> _init() async {
    if (_isInitialized) return;

    // Initialiser vodozemac (crypto E2E) AVANT le client : le SDK n'active
    // le chiffrement que si vodozemac est déjà initialisé.
    if (!vod.isInitialized()) {
      await flutter_vod.init();
    }

    // Sur le web, ni sqflite ni chemin de fichier : le SDK bascule tout seul
    // sur IndexedDB quand on ne lui donne pas de base. Lui passer une base
    // SQLite ferait lever `path_provider` avant même l'ouverture.
    final matrixDb = estWeb
        ? await MatrixSdkDatabase.init(MatrixConstants.applicationName)
        : await MatrixSdkDatabase.init(
            MatrixConstants.applicationName,
            database: await openDatabase(
              '${await _getDatabasePath()}/${MatrixConstants.applicationName}.db',
            ),
          );

    // `ClientRempart` et non `Client` : il refuse d'écrire en clair dans un
    // salon chiffré quand vodozemac n'a pas démarré (voir sa documentation).
    _client = ClientRempart(
      MatrixConstants.applicationName,
      database: matrixDb,
      // Sans cette déclaration, le SDK jette **toutes** les demandes de
      // vérification entrantes, en silence : `handleToDeviceEvent` sort
      // immédiatement si `verificationMethods` est vide. Un autre appareil
      // pouvait donc demander à se vérifier sans que rien n'apparaisse ici.
      // Vu à l'essai, avec un client tiers qui attendait dans le vide.
      verificationMethods: {
        KeyVerificationMethod.emoji,
        KeyVerificationMethod.numbers,
        // Afficher un QR est possible partout ; le scanner suppose une
        // caméra, que le navigateur n'offre pas de façon fiable. Déclarer
        // `qrScan` sur le web ferait proposer à l'utilisateur un choix qui
        // n'aboutirait jamais.
        KeyVerificationMethod.qrShow,
        if (!estWeb) KeyVerificationMethod.qrScan,
      },
    );
    _brancherVerifications();

    // Restaurer la session précédente si elle existe.
    //
    // `waitForFirstSync` vaut vrai par défaut : l'initialisation attend alors
    // un `/sync` complet avec le serveur. Serveur injoignable (VPN coupé,
    // métro, wifi captif) et l'application ne démarrait jamais, écran noir
    // sans message ni bouton. La base locale contient déjà les conversations :
    // on ouvre dessus, la synchronisation rattrape ensuite.
    await _client!.init(waitForFirstSync: false);

    debugPrint(
      'Matrix: chiffrement client activé = ${_client!.encryptionEnabled}',
    );

    _isInitialized = true;

    // Les capacités du serveur sont mises en cache **3 jours** par le SDK, sur
    // disque. Après une mise à jour du serveur, l'app continue donc de croire
    // qu'il ne sait pas servir les médias authentifiés, et tape l'ancienne
    // route, gelée depuis Matrix 1.11 : tous les avatars retombent en 404
    // pendant trois jours. On rafraîchit une fois au démarrage, en tâche de
    // fond pour ne pas retarder l'affichage.
    unawaited(() async {
      try {
        // 1 ms et non `Duration.zero` : à zéro, le SDK interroge bien le
        // serveur mais n'écrit rien en cache, et l'appel suivant relit la
        // valeur périmée. Une durée non nulle force la relecture ET la
        // réécriture.
        await _client!
            .getVersions(cacheLifetime: const Duration(milliseconds: 1));
      } catch (e) {
        // Le cache précédent reste utilisable : hors ligne, ce n'est pas grave.
        debugPrint('Matrix: capacités du serveur non rafraîchies ($e)');
      }
    }());

    // Auto-accepter les invitations entrantes : UX messenger (Signal/Telegram),
    // la conversation apparaît toute seule chez le destinataire, sans étape
    // « accepter ». Sans ça, une invitation reste invisible (roomsProvider ne
    // liste que les rooms `join`).
    _setupAutoJoinInvites();

    // Notifications locales des nouveaux messages : le SDK filtre déjà via les
    // push rules, on se contente de les afficher.
    final client = _client;
    if (client != null) {
      unawaited(NotificationService.instance.ecouter(client));
    }
  }

  final Set<String> _joiningInvites = {};
  final Set<String> _markedDirect = {};

  /// Écoute les syncs et rejoint automatiquement les rooms où l'on est invité.
  void _setupAutoJoinInvites() {
    _client?.onSync.stream.listen((_) => _autoJoinInvites());
    // Passe initiale : des invitations peuvent déjà être là au démarrage.
    _autoJoinInvites();
  }

  /// Force une synchronisation immédiate et attend qu'elle se termine.
  ///
  /// La boucle de sync se rattrape déjà seule (le SDK réessaie toutes les
  /// 3 secondes après une erreur) ; cette méthode sert au geste « tirer pour
  /// rafraîchir », qui doit rendre la main vite et non attendre la fin du
  /// long-poll en cours. D'où l'abandon préalable : sans lui, `oneShotSync`
  /// se contente d'attendre la requête déjà en vol, jusqu'à sa fin.
  Future<void> resynchroniser() async {
    final client = _client;
    if (client == null || !client.isLogged()) return;
    await client.abortSync();
    try {
      await client.oneShotSync(timeout: const Duration(seconds: 10));
    } finally {
      // `abortSync` a coupé la boucle de fond : sans ça, plus rien ne
      // syncerait après un rafraîchissement manuel.
      client.backgroundSync = true;
    }
  }

  Future<void> _autoJoinInvites() async {
    final client = _client;
    if (client == null) {
      return;
    }
    for (final room in client.rooms) {
      if (room.membership == Membership.invite) {
        if (!_joiningInvites.add(room.id)) {
          continue; // déjà un join en cours pour cette room
        }
        // `is_direct` n'est lisible que sur l'invitation (avant de rejoindre) :
        // on capture l'expéditeur du DM ici pour le réinscrire dans m.direct.
        final dmUser = room.directChatMatrixID;
        try {
          await room.join();
          if (dmUser != null) {
            await room.addToDirectChat(dmUser);
          }
          debugPrint('Matrix: invitation auto-acceptée (${room.id})');
        } catch (e) {
          debugPrint('Matrix: échec auto-join ${room.id}: $e');
          _joiningInvites.remove(room.id); // réessayer au prochain sync
        }
        continue;
      }

      // Rooms rejointes ressemblant à un tête-à-tête (sans nom, un seul autre
      // membre) mais non marquées m.direct : les réinscrire, sinon isDirectChat
      // reste faux (présence, titre de repli). Cas typique : invitation
      // auto-rejointe avant ce correctif, ou reçue sans is_direct.
      if (room.membership == Membership.join &&
          room.directChatMatrixID == null &&
          room.name.isEmpty &&
          !_markedDirect.contains(room.id)) {
        final heroes = room.summary.mHeroes;
        final contact =
            (heroes != null && heroes.length == 1) ? heroes.first : null;
        if (contact == null) {
          continue; // heroes pas encore chargés : réessayer au prochain sync
        }
        _markedDirect.add(room.id);
        try {
          await room.addToDirectChat(contact);
          debugPrint('Matrix: room marquée directe (${room.id} <- $contact)');
        } catch (e) {
          debugPrint('Matrix: échec marquage direct ${room.id}: $e');
          _markedDirect.remove(room.id); // réessayer au prochain sync
        }
      }
    }
  }

  /// Obtient le chemin de la base de données
  /// Aligne le nom affiché côté Matrix sur celui du profil Supabase.
  ///
  /// Les noms vivent dans Supabase, et Matrix n'en savait rien : le serveur ne
  /// connaissait que `u_<uuid>`. Or tout ce qui lit un nom **hors de
  /// l'application** passe par le profil Matrix, et se retrouvait donc devant
  /// un identifiant illisible :
  ///
  /// - la notification composée dans l'isolate d'arrière-plan, qui n'a aucun
  ///   accès à Supabase et retombait sur « Rempart » faute de nom ;
  /// - les bots, qui résolvent l'auteur d'un message de groupe par
  ///   `/profile/{mxid}/displayname` pour donner le fil au modèle.
  ///
  /// Best-effort : un échec ne doit pas gêner la connexion. Rien n'est envoyé
  /// si le nom est vide, inchangé, ou n'est qu'un identifiant (Synapse pose le
  /// localpart par défaut, et il ne faut surtout pas le recopier).
  Future<void> harmoniserNomAffiche(String? nom) async {
    final client = _client;
    final voulu = nom?.trim() ?? '';
    if (client == null || !client.isLogged() || voulu.isEmpty) return;
    final userId = client.userID;
    if (userId == null || estUnIdentifiant(voulu, userId)) return;

    try {
      // La lecture ne doit jamais empêcher l'écriture : sur un compte qui n'a
      // jamais eu de profil, Synapse répond M_UNKNOWN « No row found », et
      // remonter cette erreur reviendrait à ne poser le nom que là où il y en
      // avait déjà un, c'est-à-dire nulle part où c'était utile.
      String? actuel;
      try {
        actuel = (await client.getProfileFromUserId(userId)).displayName;
      } catch (_) {
        actuel = null;
      }
      if (actuel == voulu) return;
      await client.setProfileField(userId, 'displayname', {
        'displayname': voulu,
      });
      debugPrint('Matrix: nom affiché harmonisé');
    } catch (e) {
      // Serveur ancien, hors ligne, permission refusée : sans conséquence, le
      // nom reste résolu depuis Supabase partout où l'app le peut.
      debugPrint('Matrix: nom affiché non harmonisé ($e)');
    }
  }

  Future<String> _getDatabasePath() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return dir.path;
    } catch (e) {
      return '.';
    }
  }

  /// Connexion avec identifiants Matrix
  Future<LoginResponse> login({
    required String username,
    required String password,
  }) async {
    if (!_isInitialized) {
      await init();
    }

    // Configurer le homeserver
    await _client!.checkHomeserver(
      Uri.parse(MatrixConstants.homeserver),
    );

    // Se connecter
    return _client!.login(
      LoginType.mLoginPassword,
      identifier: AuthenticationUserIdentifier(user: username),
      password: password,
      initialDeviceDisplayName: MatrixConstants.applicationName,
    );
  }

  /// Connexion avec token existant (pour intégration Supabase)
  Future<void> loginWithToken({
    required String userId,
    required String accessToken,
    required String deviceId,
  }) async {
    if (!_isInitialized) {
      await init();
    }

    await _client!.checkHomeserver(
      Uri.parse(MatrixConstants.homeserver),
    );

    // Restaurer la session avec le token
    await _client!.init(
      newToken: accessToken,
      newUserID: userId,
      newHomeserver: Uri.parse(MatrixConstants.homeserver),
      newDeviceName: MatrixConstants.applicationName,
      newDeviceID: deviceId,
    );
  }

  /// Inscription d'un nouvel utilisateur
  Future<void> register({
    required String username,
    required String password,
    String? displayName,
  }) async {
    if (!_isInitialized) {
      await init();
    }

    await _client!.checkHomeserver(
      Uri.parse(MatrixConstants.homeserver),
    );

    debugPrint(
        'Matrix register: username=$username, homeserver=${MatrixConstants.homeserver}');

    // Inscription avec dummy auth pour serveur sans vérification
    try {
      await _client!.register(
        username: username,
        password: password,
        initialDeviceDisplayName: MatrixConstants.applicationName,
        auth: AuthenticationData(type: AuthenticationTypes.dummy),
      );
    } catch (e) {
      // Si l'erreur est liée à UIA, essayer sans auth
      debugPrint('Register with dummy failed: $e, trying without auth...');
      await _client!.register(
        username: username,
        password: password,
        initialDeviceDisplayName: MatrixConstants.applicationName,
      );
    }

    // Un nom absent n'est pas une erreur, et un echec de pose non plus :
    // arriver sans nom affiche est un desagrement, refuser l'inscription pour
    // cela en serait un vrai.
    if (displayName != null && displayName.isNotEmpty) {
      try {
        await definirNomAffiche(displayName);
      } catch (e) {
        debugPrint('Failed to set display name: $e');
      }
    }
  }


  // ============================================
  // Durcissement E2E (cross-signing + sauvegarde de clés)
  // ============================================

  /// Fait notifier les réactions, que Matrix passe sous silence par défaut.
  ///
  /// La spécification prévoit une règle `.m.rule.reaction` qui écarte les
  /// `m.reaction` de toute notification. C'est un choix raisonnable pour un
  /// salon public bruyant, mais pas ici : dans Rempart, une réaction est la
  /// façon de répondre à un agent qui demande une validation, et ne pas savoir
  /// qu'on a été lu vide le geste de son sens.
  ///
  /// Désactiver la règle agit des deux côtés d'un coup : le serveur se met à
  /// pousser les réactions, et le SDK, qui évalue les mêmes règles en local,
  /// cesse de les écarter de `onNotification`.
  ///
  /// Best-effort : un serveur qui refuse ne doit pas faire échouer la
  /// connexion. Le tri (ne garder que les réactions à ses propres messages) se
  /// fait côté application, la règle Matrix ne sachant pas l'exprimer.
  Future<void> activerNotificationsDeReaction() async {
    final client = _client;
    if (client == null) return;
    try {
      await client.setPushRuleEnabled(
        PushRuleKind.override,
        '.m.rule.reaction',
        false,
      );
    } catch (e) {
      // Règle absente sur ce serveur : rien à désactiver, donc rien à signaler.
      debugPrint('MatrixService: règle de réaction non modifiée ($e)');
    }
  }

  /// Met en place, ou déverrouille sur un appareil connu, le durcissement E2E :
  /// SSSS (passphrase = mot de passe utilisateur) + cross-signing + sauvegarde
  /// de clés en ligne, puis auto-vérifie cet appareil.
  ///
  /// Retourne la recovery key SI un nouveau SSSS a été créé (à faire sauvegarder
  /// par l'utilisateur), sinon null.
  Future<String?> setupOrUnlockEncryption(
    String passphrase,
    String matrixPassword,
  ) async {
    final client = _client;
    final encryption = client?.encryption;
    if (client == null || encryption == null || !encryption.enabled) {
      return null;
    }

    final crossSigning = encryption.crossSigning;
    final keyManager = encryption.keyManager;

    // Déjà configuré ET en cache sur cet appareil : rien à faire.
    if (crossSigning.enabled &&
        await crossSigning.isCached() &&
        keyManager.enabled &&
        await keyManager.isCached()) {
      return null;
    }

    return _bootstrapE2e(
      passphraseOuverture: passphrase,
      passphraseCible: passphrase,
      matrixPassword: matrixPassword,
      reutiliserSsss: true,
      // Le login ne doit pas rester suspendu à cette mise en place : passé ce
      // délai on rend la main sans clé plutôt que de bloquer l'écran.
      surTimeout: () => null,
    );
  }

  /// Re-chiffre le SSSS de [ancienne] vers [nouvelle] phrase secrète et rend la
  /// nouvelle clé de récupération.
  ///
  /// Les secrets (cross-signing, sauvegarde de clés) sont **migrés** vers la
  /// clé neuve, pas réinitialisés : l'historique chiffré reste accessible.
  ///
  /// À appeler AVANT de changer le mot de passe côté Supabase. Tant que ce
  /// dernier n'a pas bougé, l'ancienne phrase secrète est toujours celle du
  /// compte : un échec ici se rattrape par un simple nouvel essai. Dans l'ordre
  /// inverse, l'utilisateur se retrouverait avec un compte au nouveau mot de
  /// passe et des clés fermées par l'ancien, qu'il vient d'abandonner.
  ///
  /// Un dépassement de délai est une erreur, et non un abandon silencieux :
  /// l'appelant doit pouvoir renoncer au changement plutôt que de le poursuivre
  /// sur un résultat incertain.
  Future<String?> rechiffrerSsss(
    String ancienne,
    String nouvelle,
    String matrixPassword,
  ) {
    return _bootstrapE2e(
      passphraseOuverture: ancienne,
      passphraseCible: nouvelle,
      matrixPassword: matrixPassword,
      reutiliserSsss: false,
      delai: const Duration(seconds: 90),
    );
  }

  /// Rouvre le coffre avec la **clé de récupération** (ou l'ancien mot de
  /// passe, le SDK reconnaît les deux) et le referme sur le nouveau mot de
  /// passe.
  ///
  /// C'est la voie qui préserve l'historique : les secrets sont migrés vers
  /// une clé neuve plutôt que recréés, donc la sauvegarde de clés reste
  /// lisible et les anciens messages aussi. Rend la nouvelle clé de
  /// récupération, à montrer une fois.
  Future<String?> rouvrirSsssAvec(
    String cleOuPhrase,
    String nouveau,
    String matrixPassword,
  ) {
    return _bootstrapE2e(
      passphraseOuverture: cleOuPhrase,
      passphraseCible: nouveau,
      matrixPassword: matrixPassword,
      reutiliserSsss: false,
      delai: const Duration(seconds: 90),
    );
  }

  /// Repart d'un coffre neuf, l'ancien étant définitivement fermé.
  ///
  /// À n'appeler que lorsque ni le mot de passe ni la clé de récupération ne
  /// sont connus : le SSSS, le cross-signing et la sauvegarde de clés en ligne
  /// sont **effacés** puis recréés. Tout ce que l'ancien coffre gardait
  /// devient illisible pour toujours, y compris les messages reçus avant.
  /// Les autres appareils du compte devront être reconfirmés.
  Future<String?> reinitialiserChiffrement(
    String nouveau,
    String matrixPassword,
  ) {
    return _bootstrapE2e(
      passphraseOuverture: nouveau,
      passphraseCible: nouveau,
      matrixPassword: matrixPassword,
      reutiliserSsss: false,
      toutEffacer: true,
      delai: const Duration(seconds: 90),
    );
  }

  /// Déroule un bootstrap E2E et rend la clé de récupération si une nouvelle
  /// clé SSSS a été créée.
  ///
  /// [passphraseOuverture] ouvre le SSSS déjà en place, [passphraseCible]
  /// chiffre celui d'arrivée. Les deux se confondent au login, où l'on ne fait
  /// que déverrouiller. Elles diffèrent au changement de mot de passe, seul cas
  /// où [reutiliserSsss] vaut faux : refuser la clé existante est précisément
  /// ce qui pousse le SDK à migrer les secrets vers une clé neuve
  /// (`migrateSecretsToKey`) plutôt qu'à rouvrir l'ancienne.
  ///
  /// Sans [surTimeout], un dépassement de [delai] lève ; avec, sa valeur est
  /// rendue à la place.
  Future<String?> _bootstrapE2e({
    required String passphraseOuverture,
    required String passphraseCible,
    required String matrixPassword,
    required bool reutiliserSsss,
    Duration delai = const Duration(seconds: 45),
    String? Function()? surTimeout,
    bool toutEffacer = false,
  }) async {
    final client = _client;
    final encryption = client?.encryption;
    if (client == null || encryption == null) return null;
    final crossSigning = encryption.crossSigning;

    final completer = Completer<String?>();
    var createdNewSsss = false;

    // Répondre à l'UIA (ré-auth) déclenchée par l'upload des clés cross-signing,
    // avec le mot de passe Matrix du compte.
    final uiaSub = client.onUiaRequest.stream.listen((uia) async {
      if (uia.state == UiaRequestState.waitForUser &&
          uia.nextStages.contains(AuthenticationTypes.password)) {
        try {
          await uia.completeStage(
            AuthenticationPassword(
              session: uia.session,
              password: matrixPassword,
              identifier: AuthenticationUserIdentifier(
                user: client.userID!.localpart!,
              ),
            ),
          );
        } catch (e) {
          debugPrint('E2E UIA: échec completeStage: $e');
        }
      }
    });

    encryption.bootstrap(
      onUpdate: (bootstrap) async {
        try {
          final state = bootstrap.state;
          if (state == BootstrapState.askWipeSsss) {
            // `toutEffacer` : le coffre ne peut plus être ouvert (mot de passe
            // oublié, clé de récupération perdue), on repart de zéro.
            bootstrap.wipeSsss(toutEffacer);
          } else if (state == BootstrapState.askBadSsss) {
            bootstrap.ignoreBadSecrets(true);
          } else if (state == BootstrapState.askUseExistingSsss) {
            bootstrap.useExistingSsss(!toutEffacer && reutiliserSsss);
          } else if (state == BootstrapState.askUnlockSsss) {
            for (final key in bootstrap.oldSsssKeys!.values) {
              // `keyOrPassphrase` : le SDK reconnaît de lui-même une clé de
              // récupération d'une phrase secrète. L'utilisateur peut donc
              // coller l'une ou l'autre sans qu'on lui demande laquelle.
              await key.unlock(keyOrPassphrase: passphraseOuverture);
            }
            bootstrap.unlockedSsss();
          } else if (state == BootstrapState.openExistingSsss) {
            await bootstrap.newSsssKey!
                .unlock(keyOrPassphrase: passphraseOuverture);
            await bootstrap.openExistingSsss();
          } else if (state == BootstrapState.askNewSsss) {
            createdNewSsss = true;
            await bootstrap.newSsss(passphraseCible);
          } else if (state == BootstrapState.askWipeCrossSigning) {
            await bootstrap.wipeCrossSigning(toutEffacer);
          } else if (state == BootstrapState.askSetupCrossSigning) {
            await bootstrap.askSetupCrossSigning(
              setupMasterKey: true,
              setupSelfSigningKey: true,
              setupUserSigningKey: true,
            );
          } else if (state == BootstrapState.askWipeOnlineKeyBackup) {
            bootstrap.wipeOnlineKeyBackup(toutEffacer);
          } else if (state == BootstrapState.askSetupOnlineKeyBackup) {
            await bootstrap.askSetupOnlineKeyBackup(true);
          } else if (state == BootstrapState.done) {
            if (!completer.isCompleted) {
              completer.complete(
                createdNewSsss ? bootstrap.newSsssKey?.recoveryKey : null,
              );
            }
          } else if (state == BootstrapState.error) {
            if (!completer.isCompleted) {
              completer.completeError(Exception('Bootstrap E2E échoué'));
            }
          }
        } catch (e) {
          if (!completer.isCompleted) completer.completeError(e);
        }
      },
    );

    try {
      final recoveryKey = surTimeout == null
          ? await completer.future.timeout(delai)
          : await completer.future.timeout(delai, onTimeout: surTimeout);

      // Auto-vérifier cet appareil via le cross-signing.
      try {
        if (crossSigning.enabled && await crossSigning.isCached()) {
          await crossSigning.selfSign(passphrase: passphraseCible);
        }
      } catch (e) {
        debugPrint('Matrix: self-sign échoué: $e');
      }
      return recoveryKey;
    } finally {
      await uiaSub.cancel();
    }
  }

  // ============================================
  // Profil et sessions du compte
  // ============================================

  /// Change le nom affiché du compte côté Matrix.
  ///
  /// Dans l'app, les noms viennent de Supabase ; celui-ci est pourtant à tenir
  /// à jour, car c'est le seul que voient les **bots** : la gateway et le
  /// plugin Maubot résolvent les auteurs d'un fil par
  /// `/profile/{mxid}/displayname` pour donner le contexte au modèle. Sans
  /// cette copie, un utilisateur renommé resterait un `@u_<uuid>` illisible
  /// dans les conversations de groupe.
  Future<void> definirNomAffiche(String nom) async {
    final client = _client;
    final userId = client?.userID;
    if (client == null || userId == null) return;
    await client.setProfileField(userId, 'displayname', {'displayname': nom});
  }

  /// Identifiant de la session courante, pour la distinguer des autres.
  String? get appareilCourant => _client?.deviceID;

  /// Clés d'un appareil du compte, d'où se lit son état de vérification.
  ///
  /// Rend null tant que le SDK n'a pas chargé les clés de l'utilisateur, ce qui
  /// arrive juste après le démarrage : l'appelant affiche alors « inconnu »
  /// plutôt que « non vérifié », qui serait un mensonge.
  DeviceKeys? clesAppareil(String deviceId) {
    final client = _client;
    final moi = client?.userID;
    if (client == null || moi == null) return null;
    return client.userDeviceKeys[moi]?.deviceKeys[deviceId];
  }

  /// Demande la vérification d'un de nos appareils.
  ///
  /// Les deux côtés compareront une suite d'emojis. C'est le seul moment où
  /// l'on établit qu'un appareil est bien le nôtre : sans cela, le chiffrement
  /// garantit que personne d'autre que « les appareils du compte » ne lit, sans
  /// jamais dire qui ils sont.
  Future<KeyVerification?> verifierAppareil(String deviceId) async {
    final cles = clesAppareil(deviceId);
    if (cles == null) return null;
    return cles.startVerification();
  }

  /// Vrai tant que cette session n'a été confirmée par aucun autre appareil.
  ///
  /// C'est la question que le SDK se pose avant d'aller chercher quoi que ce
  /// soit dans la sauvegarde de clés en ligne (`isUnknownSession`) : tant
  /// qu'elle est vraie, il ne demande rien, et **tous** les messages restent
  /// illisibles, même ceux dont la clé dort sur le serveur.
  ///
  /// Rend faux tant que les clés du compte ne sont pas chargées : on ne
  /// dérange pas un autre appareil sur une question à laquelle on ne sait pas
  /// encore répondre.
  bool get sessionAConfirmer {
    final client = _client;
    final moi = client?.userID;
    final ici = client?.deviceID;
    if (client == null || moi == null || ici == null) return false;
    if (!client.encryptionEnabled) return false;
    final miennes = client.userDeviceKeys[moi];
    final celleci = miennes?.deviceKeys[ici];
    if (miennes == null || celleci == null) return false;
    if (celleci.signed) return false;
    // Personne à qui demander : une première session n'a pas d'aîné.
    return miennes.deviceKeys.keys.any((id) => id != ici);
  }

  /// Une seule demande par lancement : refusée ou interrompue, elle se
  /// represente à la prochaine ouverture de l'application, pas en boucle.
  bool _confirmationDemandee = false;

  /// Demande aux autres appareils du compte de confirmer cette session.
  ///
  /// Une session ouverte par QR n'a jamais vu le mot de passe, qui est aussi
  /// la phrase secrète du coffre SSSS : elle ne peut donc pas l'ouvrir seule,
  /// reste non signée, et n'a accès à aucune clé de l'historique. La
  /// confirmation par un appareil déjà connu est la seule façon d'en sortir
  /// sans redemander le mot de passe : une fois l'échange terminé, le SDK
  /// réclame les secrets à l'appareil qui a confirmé (clés de cross-signing et
  /// clé de la sauvegarde), et les anciens messages redeviennent lisibles.
  ///
  /// La demande vise **un** appareil, le plus récemment actif, et non tous les
  /// siens à la fois. La diffusion (`deviceId: '*'`) existe dans le SDK mais
  /// ne sert à rien ici : elle ne retient que les appareils dont la chaîne de
  /// signatures se valide (`hasValidSignatureChain`), or une session qui n'a
  /// pas ouvert le coffre n'en valide aucune. La liste filtrée était donc
  /// vide, la demande ne partait à personne sans la moindre erreur, et
  /// l'écran attendait indéfiniment une réponse que rien n'avait demandée.
  Future<KeyVerification?> demanderConfirmationDeSession() async {
    if (_confirmationDemandee || !sessionAConfirmer) return null;
    final ici = _client?.deviceID;
    if (ici == null) return null;

    // `appareils()` rend la liste du plus récemment vu au plus ancien : c'est
    // la meilleure approximation de « celui qu'il a sous la main ».
    for (final appareil in await appareils()) {
      if (appareil.deviceId == ici) continue;
      final cles = clesAppareil(appareil.deviceId);
      if (cles == null) continue;
      _confirmationDemandee = true;
      return cles.startVerification();
    }
    return null;
  }

  /// Demandes de vérification reçues des autres appareils du compte.
  ///
  /// Un flux à nous, et non celui du SDK relayé tel quel : l'interface s'y
  /// abonne au démarrage, alors qu'aucun client Matrix n'existe encore. Rendre
  /// le flux du client donnait `null` à ce moment-là, l'abonnement n'était
  /// jamais créé, et aucune demande n'arrivait jamais. Vu à l'essai, avec un
  /// autre client qui demandait dans le vide.
  final _demandesVerification =
      StreamController<KeyVerification>.broadcast();

  Stream<KeyVerification> get demandesDeVerification =>
      _demandesVerification.stream;

  StreamSubscription<KeyVerification>? _relaisVerification;

  /// Rebranche le relais sur le client courant.
  ///
  /// Appelé à chaque fois qu'un client naît : après un logout, c'est un
  /// nouveau client, et l'ancien abonnement ne dirait plus rien.
  void _brancherVerifications() {
    unawaited(_relaisVerification?.cancel());
    _relaisVerification = _client?.onKeyVerificationRequest.stream
        .listen(_demandesVerification.add);
  }

  /// Sessions ouvertes sur le compte, la plus récemment vue en tête.
  Future<List<Device>> appareils() async {
    final liste = await _client?.getDevices() ?? [];
    return liste
      ..sort((a, b) => (b.lastSeenTs ?? 0).compareTo(a.lastSeenTs ?? 0));
  }

  /// Ferme une session à distance.
  ///
  /// Le serveur protège cette opération par une ré-authentification (UIA). On
  /// y répond avec le mot de passe Matrix, aléatoire et gardé dans le secure
  /// storage : l'utilisateur ne l'a jamais vu et n'a donc rien à retaper.
  Future<void> fermerAppareil(String deviceId, String motDePasseMatrix) async {
    final client = _client;
    final localpart = client?.userID?.localpart;
    if (client == null || localpart == null) return;

    final uiaSub = client.onUiaRequest.stream.listen((uia) async {
      if (uia.state != UiaRequestState.waitForUser ||
          !uia.nextStages.contains(AuthenticationTypes.password)) {
        return;
      }
      await uia.completeStage(
        AuthenticationPassword(
          session: uia.session,
          password: motDePasseMatrix,
          identifier: AuthenticationUserIdentifier(user: localpart),
        ),
      );
    });

    try {
      await client.uiaRequestBackground(
        (auth) => client.deleteDevice(deviceId, auth: auth),
      );
    } finally {
      await uiaSub.cancel();
    }
  }

  // ============================================
  // Modération : bloquer et signaler
  // ============================================

  /// Utilisateurs bloqués par le compte.
  ///
  /// La liste vit dans les données de compte Matrix (`m.ignored_user_list`) :
  /// elle suit l'utilisateur d'un appareil à l'autre, et c'est le serveur qui
  /// filtre, donc rien n'arrive plus de leur part.
  List<String> get utilisateursBloques => _client?.ignoredUsers ?? const [];

  bool estBloque(String mxid) => utilisateursBloques.contains(mxid);

  /// Bloque un utilisateur : ses messages cessent d'arriver, et les
  /// conversations en tête-à-tête avec lui sont quittées.
  ///
  /// Le SDK vide aussi les messages déjà reçus de cette personne : c'est
  /// exactement ce qu'on attend d'un blocage après un harcèlement.
  Future<void> bloquerUtilisateur(String mxid) async {
    await _client?.ignoreUser(mxid);
  }

  Future<void> debloquerUtilisateur(String mxid) async {
    await _client?.unignoreUser(mxid);
  }

  /// Signale un message à l'administrateur du serveur.
  ///
  /// Le contenu du signalement n'est pas lisible par le serveur dans une
  /// conversation chiffrée : seuls l'identifiant du message, la room et le
  /// motif saisi lui parviennent. C'est peu, mais c'est ce que permet un
  /// service qui ne lit pas les messages, et cela suffit à agir sur un compte.
  Future<void> signalerMessage(
    String roomId,
    String eventId, {
    required String motif,
  }) async {
    await _client?.reportEvent(roomId, eventId, reason: motif, score: -100);
  }

  /// Déconnexion
  Future<void> logout() async {
    if (_client != null && _client!.isLogged()) {
      await _client!.logout();
    }
  }

  /// Dispose le service
  Future<void> dispose() async {
    await _relaisVerification?.cancel();
    await _demandesVerification.close();
    await _client?.dispose();
    _client = null;
    _isInitialized = false;
  }

  // ============================================
  // Gestion des Rooms (Conversations)
  // ============================================

  /// Liste des rooms jointes
  List<Room> get rooms => _client?.rooms ?? [];

  /// Récupère une room par ID
  Room? getRoom(String roomId) => _client?.getRoomById(roomId);

  /// Ce compte sait-il lire un salon chiffré, autrement dit a-t-il des clés ?
  ///
  /// La question ne se pose que pour les bots, et ils ne se valent pas : un
  /// agent qui tient son propre appareil Matrix déchiffre comme n'importe quel
  /// membre, tandis qu'un bot piloté par la passerelle n'a aucune clé et ne
  /// verrait que du charabia. Faute de les distinguer, on interdisait les deux,
  /// ce qui privait de groupe chiffré des agents parfaitement capables d'y lire.
  ///
  /// L'appel interroge le serveur plutôt que le cache `userDeviceKeys` : ce
  /// cache ne se remplit que pour les comptes avec qui un salon chiffré est
  /// déjà partagé, donc jamais pour un bot qu'on s'apprête tout juste à
  /// inviter. On y lirait un « pas de clés » systématique.
  ///
  /// Rend faux si le serveur ne répond pas : avertir à tort coûte un dialogue,
  /// promettre à tort coûte un bot muet dans un groupe.
  Future<bool> saitDechiffrer(String mxid) async {
    final client = _client;
    if (client == null) return false;
    try {
      final reponse = await client.queryKeys({mxid: []}, timeout: 10000);
      return reponse.deviceKeys?[mxid]?.isNotEmpty ?? false;
    } catch (e) {
      debugPrint('MatrixService: clés de $mxid indisponibles ($e)');
      return false;
    }
  }

  /// Crée une conversation directe.
  ///
  /// Chiffrée E2E par défaut (chat "sécurisé"). Le futur chemin "avec bot"
  /// passera `encrypted: false` (voir décision de conception E2E/bots).
  Future<String> createDirectChat(String userId,
      {bool encrypted = true}) async {
    // Chercher nous-mêmes avant de créer. `startDirectChat` ne consulte que
    // l'account data `m.direct`, qui peut ne pas mentionner une room ouverte
    // par le contact : on repartirait alors sur une création alors qu'un fil
    // existe déjà.
    final existant = await trouverChatDirect(userId);
    if (existant != null) {
      if (existant.membership == Membership.invite) {
        await existant.join();
      }
      // Réparer l'account data au passage, sinon le SDK recommencerait à la
      // prochaine ouverture.
      if (existant.directChatMatrixID != userId) {
        try {
          await existant.addToDirectChat(userId);
        } catch (e) {
          debugPrint('MatrixService: m.direct non mis à jour ($e)');
        }
      }
      return existant.id;
    }

    // `skipExistingChat` : le SDK reprendrait lui aussi une room listée dans
    // `m.direct` en ne regardant QUE notre propre appartenance, et
    // ressusciterait ainsi la room morte qu'on vient justement d'écarter.
    return _client!.startDirectChat(
      userId,
      enableEncryption: encrypted,
      skipExistingChat: true,
    );
  }

  /// Tête-à-tête déjà ouvert avec ce contact, s'il en existe un.
  ///
  /// Balaie toutes les rooms, y compris celles où l'on n'est encore
  /// qu'invité : c'est le cas quand le contact a pris l'initiative, et créer
  /// un second fil à ce moment-là est précisément ce qui fabrique les
  /// doublons.
  ///
  /// Une room que le CONTACT a quittée est écartée : y écrire ne parvient à
  /// personne, en silence, alors que notre propre appartenance donne le change
  /// (voir [contactAtteignable]).
  ///
  /// Si plusieurs conviennent (collision de création), renvoie toujours la
  /// même, celle que l'app considère comme canonique.
  Future<Room?> trouverChatDirect(String userId) async {
    final client = _client;
    if (client == null) return null;

    final candidats = client.rooms
        .where(
          (room) =>
              (room.membership == Membership.join ||
                  room.membership == Membership.invite) &&
              room.otherUserMxid == userId,
        )
        .toList()
      ..sort(comparerChatsDirects);

    for (final room in candidats) {
      if (await _contactEncoreLa(room, userId)) return room;
    }
    return null;
  }

  /// Appartenance du contact dans cette room, demandée au serveur si l'état
  /// local ne la porte pas.
  ///
  /// `requestProfile: false` volontairement : seule l'appartenance nous
  /// intéresse, et la recherche de profil du SDK fabriquerait un membre
  /// « parti » pour un inconnu, ce qui transformerait une simple ignorance en
  /// faux départ.
  Future<bool> _contactEncoreLa(Room room, String userId) async {
    try {
      final membre = await room.requestUser(
        userId,
        ignoreErrors: true,
        requestProfile: false,
      );
      return contactAtteignable(membre?.membership);
    } catch (e) {
      debugPrint('MatrixService: appartenance de $userId inconnue ($e)');
      return true;
    }
  }

  /// Crée un groupe.
  ///
  /// Chiffré E2E par défaut pour les groupes privés (chat "sécurisé").
  ///
  /// Le chiffrement fait partie de l'état INITIAL du salon, et non d'un
  /// second appel : le salon naît chiffré, sans instant où il existerait en
  /// clair, invités compris. Si le chiffrement ne tourne pas sur l'appareil,
  /// on refuse de créer le groupe plutôt que de le créer en clair : c'est ce
  /// que faisait l'ancien code, sans prévenir personne.
  Future<String> createGroup({
    required String name,
    List<String>? inviteUserIds,
    String? topic,
    bool isPublic = false,
    bool encrypted = true,
  }) async {
    final chiffre = encrypted && !isPublic;
    if (chiffre && !_client!.encryptionEnabled) {
      throw ChiffrementIndisponible();
    }
    return _client!.createRoom(
      name: name,
      topic: topic,
      invite: inviteUserIds,
      preset:
          isPublic ? CreateRoomPreset.publicChat : CreateRoomPreset.privateChat,
      visibility: isPublic ? Visibility.public : Visibility.private,
      initialState: [
        if (chiffre)
          StateEvent(
            type: EventTypes.Encryption,
            content: {
              'algorithm': Client.supportedGroupEncryptionAlgorithms.first,
            },
          ),
      ],
    );
  }

  /// Rejoint une room par ID ou alias
  Future<String> joinRoom(String roomIdOrAlias) async {
    final roomId = await _client!.joinRoom(roomIdOrAlias);
    return roomId;
  }

  /// Quitte une room
  Future<void> leaveRoom(String roomId) async {
    final room = _client!.getRoomById(roomId);
    if (room != null) {
      await room.leave();
      // Forcer la suppression de la room du cache local
      await room.forget();
      // Forcer une sync pour mettre à jour la liste des rooms
      await syncNow();
    }
  }

  /// Force une synchronisation avec le serveur
  Future<void> syncNow() async {
    if (_client == null || !_client!.isLogged()) return;

    // Attendre la prochaine synchronisation
    try {
      await _client!.oneShotSync();
    } catch (e) {
      debugPrint('Erreur sync: $e');
    }
  }

  /// Réagit à un message, ou retire sa réaction si on l'avait déjà mise.
  ///
  /// Bascule et non simple ajout : appuyer deux fois sur le même symbole est
  /// le geste attendu pour se rétracter, et réagir deux fois n'aurait aucun
  /// sens de toute façon.
  ///
  /// Les réactions ne sont pas décoratives ici : un agent qui propose « ✅ pour
  /// approuver » attend exactement cet événement, et sans elles il faut lui
  /// répondre en tapant une commande.
  Future<void> basculerReaction(
    String roomId,
    Event message,
    String symbole,
    Timeline? timeline,
  ) async {
    final client = _client;
    final room = client?.getRoomById(roomId);
    if (client == null || room == null) return;

    final mienne = timeline == null
        ? null
        : reactionDeMoi(message, timeline, symbole, client.userID);
    if (mienne != null) {
      await room.redactEvent(mienne.eventId);
      return;
    }
    await room.sendReaction(message.eventId, symbole);
  }

  /// Notre propre réaction à ce message avec ce symbole, s'il y en a une.
  static Event? reactionDeMoi(
    Event message,
    Timeline timeline,
    String symbole,
    String? moi,
  ) {
    for (final reaction
        in message.aggregatedEvents(timeline, RelationshipTypes.reaction)) {
      if (reaction.senderId != moi || reaction.redacted) continue;
      final contenu = reaction.content.tryGetMap<String, Object?>('m.relates_to');
      if (contenu?['key'] == symbole) return reaction;
    }
    return null;
  }

  /// Réactions d'un message, regroupées par symbole et rangées par ordre
  /// d'apparition.
  ///
  /// Le décompte ignore les réactions annulées : une réaction retirée reste
  /// dans la timeline sous forme d'événement effacé.
  static List<ReactionGroupee> reactionsDe(
    Event message,
    Timeline timeline,
    String? moi,
  ) {
    final parSymbole = <String, ReactionGroupee>{};
    for (final reaction
        in message.aggregatedEvents(timeline, RelationshipTypes.reaction)) {
      if (reaction.redacted) continue;
      final symbole = reaction.content
          .tryGetMap<String, Object?>('m.relates_to')?['key'] as String?;
      if (symbole == null || symbole.isEmpty) continue;
      final groupe = parSymbole[symbole] ??= ReactionGroupee(symbole);
      groupe.nombre++;
      if (reaction.senderId == moi) groupe.parMoi = true;
    }
    return parSymbole.values.toList();
  }

  /// Invite un utilisateur dans une room
  Future<void> inviteToRoom(String roomId, String userId) async {
    final room = _client!.getRoomById(roomId);
    if (room != null) {
      await room.invite(userId);
    }
  }

  /// Relève les médias hébergés par une room : pièces jointes et avatar.
  ///
  /// Se fait forcément côté client : dans une room chiffrée, l'URL `mxc` d'une
  /// pièce jointe est à l'intérieur du message chiffré, donc illisible pour le
  /// serveur. Seul un client qui déchiffre le fil peut dresser cette liste.
  ///
  /// L'historique est remonté par tranches, avec une borne : un très vieux
  /// groupe ne doit pas bloquer la suppression pendant des minutes.
  Future<List<String>> mediasDuGroupe(String roomId,
      {int maxPages = 10}) async {
    final room = _client!.getRoomById(roomId);
    if (room == null) return const [];

    final medias = <String>{};
    final avatar = room.avatarUri;
    if (avatar != null) medias.add(avatar.toString());

    try {
      final timeline = await room.getTimeline();
      var pages = 0;
      while (timeline.canRequestHistory && pages < maxPages) {
        await timeline.requestHistory(historyCount: 100);
        pages++;
      }
      void ajouter(Object? valeur) {
        if (valeur is String && valeur.startsWith('mxc://')) medias.add(valeur);
      }

      for (final event in timeline.events) {
        if (event.type != EventTypes.Message) continue;
        final contenu = event.content;
        // Chiffré, l'URL n'est pas où on l'attend : la pièce jointe passe par
        // `file.url` (avec ses clés de déchiffrement) au lieu de `url`. Ne
        // lire que `url` renvoyait une liste vide sur toute room chiffrée,
        // c'est-à-dire précisément celles qu'on veut nettoyer.
        ajouter(contenu['url']);
        final fichier = contenu['file'];
        if (fichier is Map) ajouter(fichier['url']);

        final info = contenu['info'];
        if (info is Map) {
          ajouter(info['thumbnail_url']);
          final vignette = info['thumbnail_file'];
          if (vignette is Map) ajouter(vignette['url']);
        }
      }
      timeline.cancelSubscriptions();
    } catch (e) {
      // Historique illisible : mieux vaut supprimer le groupe sans nettoyer
      // les médias que de bloquer la suppression.
      debugPrint('MatrixService: médias du groupe illisibles ($e)');
    }
    return medias.toList();
  }

  /// Supprime un groupe pour tout le monde.
  ///
  /// Matrix ne sait pas détruire une room : la seule suppression qui ait un
  /// sens côté utilisateur est de renvoyer tous les membres puis de partir,
  /// comme le fait Telegram. La room continue d'exister côté serveur, mais
  /// plus personne n'y est.
  ///
  /// Renvoie les membres qui n'ont pas pu être retirés (droits égaux aux
  /// siens) : l'appelant doit le dire, sinon la suppression semblerait totale.
  Future<List<String>> supprimerGroupe(String roomId) async {
    final room = _client!.getRoomById(roomId);
    if (room == null) return const [];

    final restants = <String>[];
    for (final membre in room.getParticipants()) {
      if (membre.id == _client!.userID) continue;
      if (membre.membership != Membership.join &&
          membre.membership != Membership.invite) {
        continue;
      }
      try {
        await room.kick(membre.id);
      } catch (e) {
        debugPrint('MatrixService: ${membre.id} non retiré ($e)');
        restants.add(membre.id);
      }
    }

    await leaveRoom(roomId);
    return restants;
  }

  /// Renomme une room (nom affiché du groupe).
  Future<void> renommerRoom(String roomId, String nom) async {
    final room = _client!.getRoomById(roomId);
    if (room != null) await room.setName(nom);
  }

  /// Change le sujet d'une room.
  Future<void> changerSujetRoom(String roomId, String sujet) async {
    final room = _client!.getRoomById(roomId);
    if (room != null) await room.setDescription(sujet);
  }

  /// Change l'avatar d'une room. `null` retire la photo.
  Future<void> changerAvatarRoom(String roomId, MatrixFile? fichier) async {
    final room = _client!.getRoomById(roomId);
    if (room != null) await room.setAvatar(fichier);
  }

  /// Change le niveau de pouvoir d'un membre (100 = administrateur, 0 = membre).
  Future<void> changerNiveauPouvoir(
    String roomId,
    String userId,
    int niveau,
  ) async {
    final room = _client!.getRoomById(roomId);
    if (room != null) await room.setPower(userId, niveau);
  }

  /// Expulse un utilisateur d'une room
  Future<void> kickFromRoom(String roomId, String userId) async {
    final room = _client!.getRoomById(roomId);
    if (room != null) {
      await room.kick(userId);
    }
  }

  // ============================================
  // Gestion des Messages
  // ============================================

  /// Envoie un message texte
  Future<String?> sendTextMessage(String roomId, String message) async {
    final room = _client!.getRoomById(roomId);
    if (room == null) return null;

    // parseCommands: false -> les messages commençant par « / » (ex. /ping vers
    // un bot) sont envoyés littéralement, pas interprétés comme commandes client.
    final eventId = await room.sendTextEvent(message, parseCommands: false);
    return eventId;
  }

  /// Envoie une réponse à un message
  Future<String?> sendReply({
    required String roomId,
    required String message,
    required Event replyTo,
  }) async {
    final room = _client!.getRoomById(roomId);
    if (room == null) return null;

    final eventId = await room.sendTextEvent(
      message,
      inReplyTo: replyTo,
      parseCommands: false,
    );
    return eventId;
  }

  /// Envoie une image
  Future<String?> sendImage({
    required String roomId,
    required MatrixFile file,
  }) async {
    final room = _client!.getRoomById(roomId);
    if (room == null) return null;
    _exigerChiffrement(room);

    final eventId = await room.sendFileEvent(file);
    return eventId;
  }

  /// Arrête un média avant son téléversement si le salon est chiffré et que
  /// le chiffrement ne tourne pas sur l'appareil.
  ///
  /// `ClientRempart` bloque le message, mais trop tard pour un média : le SDK
  /// téléverse le fichier d'abord, et le téléverserait EN CLAIR faute de
  /// chiffrement. Le serveur garderait alors la photo lisible, même si le
  /// message qui la décrit n'est jamais parti.
  void _exigerChiffrement(Room room) {
    if (room.encrypted && !_client!.encryptionEnabled) {
      throw ChiffrementIndisponible();
    }
  }

  /// Répond à un bouton d'agent : la valeur part, le libellé s'affiche.
  ///
  /// L'agent attend exactement sa valeur (« !cancel ») : c'est donc elle qui
  /// occupe le corps du message, seul champ que lisent la passerelle et les
  /// autres clients. Le libellé voyage à côté, dans un champ à nous, et
  /// Rempart l'affiche à sa place : l'utilisateur relit alors son geste
  /// (« ❌ Annuler ») plutôt qu'une commande qu'il n'a pas tapée.
  ///
  /// Sur Element, le message reste « !cancel », ce qui est correct : c'est
  /// bien ce qui a été envoyé.
  Future<String?> repondreParBouton({
    required String roomId,
    required String valeur,
    required String libelle,
  }) async {
    final room = _client!.getRoomById(roomId);
    if (room == null) return null;
    // `sendEvent` et non `sendTextEvent` : le second ne sait pas porter de
    // champ supplémentaire. Il évite au passage l'interprétation des
    // commandes, or les valeurs commencent souvent par « ! » ou « / ».
    return room.sendEvent({
      'msgtype': 'm.text',
      'body': valeur,
      'fr.rempart.libelle_bouton': libelle,
    });
  }

  /// Taille maximale d'un envoi, telle que le serveur l'annonce.
  ///
  /// Null si le serveur ne la dit pas : on laisse alors tenter plutôt que
  /// d'interdire au hasard. Le chiffre est demandé au serveur et non fixé
  /// ici : il dépend de la configuration de Synapse et du proxy devant lui.
  Future<int?> limiteEnvoi() async {
    final client = _client;
    if (client == null) return null;
    try {
      return (await client.getConfig()).mUploadSize;
    } catch (e) {
      debugPrint("MatrixService: limite d'envoi inconnue ($e)");
      return null;
    }
  }

  /// Envoie un message vocal.
  ///
  /// `MatrixAudioFile` pose `m.audio` et la durée dans `info`, ce que les
  /// autres clients Matrix savent lire. Le SDK chiffre le média de lui-même
  /// quand la room l'est, comme pour une image.
  Future<String?> envoyerVocal({
    required String roomId,
    required Uint8List octets,
    required int secondes,
    List<int> formeOnde = const [],
    String mimeType = 'audio/mp4',
    String nom = 'message vocal.m4a',
  }) async {
    final room = _client!.getRoomById(roomId);
    if (room == null) return null;
    _exigerChiffrement(room);

    return room.sendFileEvent(
      MatrixAudioFile(
        bytes: octets,
        name: nom,
        mimeType: mimeType,
        // En millisecondes : `info.duration` suit cette unité, et l'afficher
        // en secondes donnerait des vocaux d'une heure.
        duration: secondes * 1000,
      ),
      // Marque le message comme vocal plutôt que comme simple pièce jointe
      // audio (MSC3245). Element s'en sert pour dessiner une bulle de vocal ;
      // les clients qui l'ignorent affichent un fichier audio ordinaire, ce
      // qui reste lisible.
      //
      // `room.sendAudioEvent` du SDK ferait presque la même chose, mais omet
      // ce marqueur : le vocal y arriverait comme une pièce jointe.
      //
      // La silhouette (MSC3246) voyage avec le message : la recalculer à la
      // lecture obligerait chaque destinataire à décompresser l'audio entier.
      extraContent: {
        'org.matrix.msc3245.voice': const <String, dynamic>{},
        'org.matrix.msc1767.audio': <String, dynamic>{
          'duration': secondes * 1000,
          if (formeOnde.isNotEmpty) 'waveform': formeOnde,
        },
      },
    );
  }

  /// Envoie un fichier
  /// Envoie un fichier, avec une légende facultative.
  ///
  /// [albumId] réunit plusieurs médias d'un même envoi : Matrix n'a pas
  /// d'album, la marque est donc à nous, et les autres clients l'ignorent.
  ///
  /// La légende suit la convention Matrix : `body` porte le texte et
  /// `filename` le vrai nom du fichier. Sans légende, le SDK met le nom dans
  /// les deux, ce qui reste correct.
  Future<String?> sendFile({
    required String roomId,
    required MatrixFile file,
    String? caption,
    String? albumId,
  }) async {
    final room = _client!.getRoomById(roomId);
    if (room == null) return null;
    _exigerChiffrement(room);

    final texte = caption?.trim() ?? '';
    final extra = <String, dynamic>{
      if (texte.isNotEmpty) 'body': texte,
      if (albumId != null) 'fr.rempart.album': {'id': albumId},
    };
    return room.sendFileEvent(
      file,
      extraContent: extra.isEmpty ? null : extra,
    );
  }

  /// Édite un message
  Future<void> editMessage({
    required String roomId,
    required String eventId,
    required String newContent,
  }) async {
    final room = _client!.getRoomById(roomId);
    if (room == null) return;

    final event = await room.getEventById(eventId);
    if (event == null) return;

    await event.room.sendTextEvent(
      newContent,
      editEventId: eventId,
    );
  }

  /// Retire un message, qu'il soit parti ou non.
  ///
  /// Deux gestes différents sous un même mot. Un message parvenu au serveur
  /// s'efface par une **rédaction**, qui demande au serveur d'en vider le
  /// contenu. Un message **jamais parti** n'y existe pas : il n'y a rien à y
  /// effacer, il faut le retirer de la file d'envoi locale.
  ///
  /// Les confondre ne rate pas à moitié, cela ne fait rien du tout : demander
  /// la rédaction d'un envoi en échec vise un identifiant que le serveur ne
  /// connaît pas (c'est celui de la transaction locale, pas un identifiant
  /// d'événement). Le bouton « Supprimer » restait donc sans effet, et c'est
  /// exactement sur les messages qu'on veut le plus effacer : ceux que le
  /// serveur a refusés, une vidéo trop lourde par exemple, qui restent en
  /// travers du fil avec leur pastille rouge.
  Future<void> supprimerMessage(Event message, {String? raison}) async {
    if (!message.status.isSent) {
      await message.cancelSend();
      return;
    }
    await message.room.redactEvent(message.eventId, reason: raison);
  }

  /// Charge l'historique des messages
  Future<void> loadMoreMessages(String roomId, {int historyCount = 50}) async {
    final room = _client!.getRoomById(roomId);
    if (room == null) return;

    final timeline = await room.getTimeline();
    await timeline.requestHistory(historyCount: historyCount);
  }

  /// Marque les messages comme lus
  Future<void> markAsRead(String roomId) async {
    final room = _client!.getRoomById(roomId);
    if (room == null) return;

    await room.setReadMarker(
      room.lastEvent?.eventId ?? '',
      mRead: room.lastEvent?.eventId,
    );
  }

  // ============================================
  // Gestion des indicateurs de frappe
  // ============================================

  /// Envoie l'indicateur "en train d'écrire"
  Future<void> setTyping(String roomId, {required bool isTyping}) async {
    final room = _client!.getRoomById(roomId);
    if (room == null) return;

    await room.setTyping(isTyping, timeout: isTyping ? 30000 : null);
  }

  // ============================================
  // Gestion de la présence
  // ============================================

  /// Met à jour le statut de présence
  Future<void> setPresence(PresenceType presence,
      {String? statusMessage}) async {
    await _client!.setPresence(
      _client!.userID!,
      presence,
      statusMsg: statusMessage,
    );
  }

  // ============================================
  // Streams et événements
  // ============================================

  /// Stream des mises à jour de synchronisation
  Stream<SyncUpdate>? get onSync => _client?.onSync.stream;

  /// Stream de toutes les rooms
  Stream<List<Room>>? get onRoomsUpdate {
    return _client?.onSync.stream.map((_) => rooms);
  }

  // ============================================
  // Utilitaires
  // ============================================

  /// Génère l'ID Matrix complet à partir d'un nom d'utilisateur
  String getFullUserId(String username) {
    if (username.startsWith('@') && username.contains(':')) {
      return username;
    }
    return '@$username:${MatrixConstants.domain}';
  }

  /// Construit le mxid unifié d'un utilisateur à partir de son id Supabase.
  ///
  /// DOIT rester cohérent avec la création de compte (`auth_service`) :
  /// localpart = `u_<uuid sans tirets>`. Ne pas dériver du `username` du profil :
  /// c'est un schéma incompatible, le compte n'existe pas sous `@username` et
  /// l'invitation partirait vers un utilisateur fantôme.
  String matrixUserIdForSupabaseId(String supabaseId) {
    return getFullUserId('u_${supabaseId.replaceAll('-', '')}');
  }

  /// Inverse de [matrixUserIdForSupabaseId] : retrouve l'id Supabase (UUID) à
  /// partir d'un mxid unifié `@u_<uuid sans tirets>:domain`.
  ///
  /// Renvoie null si le mxid ne suit pas ce schéma (bot `@rempart_*`/`@ubot_*`,
  /// ou autre compte) : dans ce cas il n'y a pas de profil Supabase associé.
  String? supabaseIdFromMatrixUserId(String mxid) {
    final localpart = getLocalpart(mxid);
    if (!localpart.startsWith('u_')) return null;
    final hex = localpart.substring(2);
    if (hex.length != 32 || !RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(hex)) {
      return null;
    }
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  /// Extrait le nom local d'un ID Matrix
  String getLocalpart(String userId) {
    if (userId.startsWith('@')) {
      final colonIndex = userId.indexOf(':');
      if (colonIndex > 0) {
        return userId.substring(1, colonIndex);
      }
      return userId.substring(1);
    }
    return userId;
  }

  /// Obtient le nom d'affichage d'un utilisateur
  Future<String?> getUserDisplayName(String userId) async {
    try {
      final profile = await _client!.getProfileFromUserId(userId);
      return profile.displayName;
    } catch (e) {
      debugPrint('Erreur récupération profil: $e');
      return null;
    }
  }

  /// Obtient l'avatar d'un utilisateur
  Future<Uri?> getUserAvatarUrl(String userId) async {
    try {
      final profile = await _client!.getProfileFromUserId(userId);
      return profile.avatarUrl;
    } catch (e) {
      debugPrint('Erreur récupération avatar: $e');
      return null;
    }
  }
}


/// Une réaction et son décompte, tels qu'affichés sous un message.
class ReactionGroupee {
  ReactionGroupee(this.symbole);

  final String symbole;
  int nombre = 0;

  /// Vrai si l'on fait partie de ceux qui ont réagi ainsi : la pastille se
  /// distingue alors, et un nouvel appui retire la réaction.
  bool parMoi = false;
}
