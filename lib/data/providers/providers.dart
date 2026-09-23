import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../core/constants/supabase_constants.dart';
import '../models/bot.dart';
import '../models/matrix_extensions.dart';
import '../models/profile.dart';
import '../services/archive_service.dart';
import '../services/bot_gateway_service.dart';
import '../services/matrix_service.dart';
import '../services/profile_service.dart';

// ============================================
// Services Providers
// ============================================

/// Provider pour le client Supabase
final supabaseClientProvider = Provider<supabase.SupabaseClient>((ref) {
  return supabase.Supabase.instance.client;
});

/// Provider pour le service de profils (Supabase)
final profileServiceProvider = Provider<ProfileService>((ref) {
  return ProfileService(ref.watch(supabaseClientProvider));
});

/// Provider pour le service de la Bot Gateway (bots utilisateurs)
final botGatewayServiceProvider = Provider<BotGatewayService>((ref) {
  return BotGatewayService();
});

/// Commandes declarees par les bots de l'utilisateur, indexees par mxid.
///
/// Sert a proposer la liste des le « / » dans une conversation avec un bot,
/// comme le fait Telegram. Charge une fois : une commande declaree ne change
/// que lorsque son proprietaire l'edite, et un echec (gateway injoignable)
/// rend une table vide - la saisie continue de fonctionner, sans suggestion.
final commandesDesBotsProvider =
    FutureProvider<Map<String, List<BotCommand>>>((ref) async {
  // Le catalogue d'abord : il est en dur, donc disponible même sans réseau.
  final parMxid = <String, List<BotCommand>>{
    for (final bot in botCatalogue)
      if (bot.commandes.isNotEmpty) bot.matrixId: bot.commandes,
  };

  try {
    final liste = await ref.watch(botGatewayServiceProvider).myBots();
    for (final bot in liste.bots) {
      // Ce que le bot **déclare** fait foi : les agents Hermes annoncent déjà
      // `/stop`, `/new`, `/steer` et les autres, et une commande qui change
      // là-bas n'a pas à attendre une nouvelle version de l'application.
      // Un bot qui ne déclare rien reçoit le minimum que tous comprennent,
      // plutôt qu'un menu vide.
      parMxid[bot.mxid] =
          bot.commands.isEmpty ? _commandesParDefaut : bot.commands;
    }
  } catch (e) {
    // Passerelle injoignable : le catalogue reste, le reste attendra. Mieux
    // vaut un menu partiel qu'un menu faux.
    debugPrint('commandes des bots indisponibles ($e)');
  }
  return parMxid;
});

/// Ce que comprend n'importe quel bot, faute de déclaration.
const _commandesParDefaut = <BotCommand>[
  BotCommand('/start', 'Démarrer la conversation'),
  BotCommand('/help', 'Afficher les commandes disponibles'),
  BotCommand('/stop', 'Arrêter ce qui est en cours'),
];

/// Provider pour le service Matrix (singleton)
final matrixServiceProvider = Provider<MatrixService>((ref) {
  return MatrixService.instance;
});

/// Provider pour le client Matrix
final matrixClientProvider = Provider<matrix.Client?>((ref) {
  // Observer le notifier pour se rafraîchir quand l'état change
  ref.watch(matrixStateNotifierProvider);
  return ref.watch(matrixServiceProvider).client;
});

// ============================================
// Auth Providers (Supabase)
// ============================================

/// Provider pour l'état de l'utilisateur courant (Supabase)
final currentUserProvider = StreamProvider<supabase.User?>((ref) {
  return supabase.Supabase.instance.client.auth.onAuthStateChange.map(
    (event) => event.session?.user,
  );
});

/// Provider pour l'ID de l'utilisateur courant (Supabase)
final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(currentUserProvider).value?.id;
});

/// Provider pour l'ID Matrix de l'utilisateur courant.
///
/// `ref.watch(matrixServiceProvider)` ne suffit pas : ce provider rend un
/// **singleton**, un objet dont l'identité ne change jamais. Sans le compteur
/// ci-dessous, la valeur était donc calculée une seule fois puis gardée pour
/// toute la vie de l'application. Après un changement de compte, les messages
/// de l'utilisateur étaient comparés à l'identité de l'ancien : ses propres
/// bulles s'affichaient comme celles d'un autre participant.
final currentMatrixUserIdProvider = Provider<String?>((ref) {
  ref.watch(matrixStateNotifierProvider);
  return ref.watch(matrixServiceProvider).currentUserId;
});

// ============================================
// Profile Providers (Supabase)
// ============================================

/// Provider pour le profil de l'utilisateur courant
final currentProfileProvider = FutureProvider<Profile?>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;

  final profileService = ref.watch(profileServiceProvider);
  return profileService.getProfile(userId);
});

/// Provider pour un profil spécifique
final profileProvider =
    FutureProvider.family<Profile?, String>((ref, userId) async {
  final profileService = ref.watch(profileServiceProvider);
  return profileService.getProfile(userId);
});

/// Provider pour la recherche de profils
final profileSearchProvider =
    FutureProvider.family<List<Profile>, String>((ref, query) async {
  if (query.isEmpty) return [];

  final profileService = ref.watch(profileServiceProvider);
  return profileService.searchProfiles(query);
});

/// Provider pour observer le profil en temps réel
final profileStreamProvider =
    StreamProvider.family<Profile, String>((ref, userId) {
  final profileService = ref.watch(profileServiceProvider);
  return profileService.watchProfile(userId);
});

// ============================================
// Matrix Room Providers (Conversations)
// ============================================

/// Provider pour la liste des rooms (conversations) - non archivées
final roomsProvider = Provider<List<matrix.Room>>((ref) {
  // Écouter le notifier pour forcer le rafraîchissement
  ref.watch(matrixStateNotifierProvider);

  // Accéder directement au client Matrix (singleton)
  final client = MatrixService.instance.client;
  if (client == null) {
    debugPrint('roomsProvider: client is null');
    return [];
  }

  // Récupérer les rooms archivées
  final archivedIds = ArchiveService.instance.archivedRoomIds;

  // Filtrer pour ne garder que les rooms où l'utilisateur est membre ET non archivées
  final joinedRooms = client.rooms
      .where(
        (room) =>
            room.membership == matrix.Membership.join &&
            !archivedIds.contains(room.id),
      )
      .toList();

  debugPrint(
      'roomsProvider: total=${client.rooms.length}, joined=${joinedRooms.length}, archived=${archivedIds.length}');
  return _dedoublonnerChatsDirects(joinedRooms);
});

/// N'affiche qu'un fil par contact.
///
/// Deux personnes qui s'écrivent simultanément, avant que l'invitation de
/// l'autre ne soit parvenue, créent chacune une room : Matrix les accepte
/// toutes les deux et la liste montrait alors deux entrées pour le même
/// contact. La room canonique (voir `comparerChatsDirects`) est seule
/// conservée.
///
/// Prudence délibérée : une room qui porte des messages n'est JAMAIS masquée,
/// même en doublon. Cacher un fil revient à cacher des messages ; tant qu'on
/// ne sait pas fusionner deux historiques, deux entrées valent mieux qu'une
/// conversation escamotée. Seuls les doublons restés vides disparaissent.
List<matrix.Room> _dedoublonnerChatsDirects(List<matrix.Room> rooms) {
  final parContact = <String, List<matrix.Room>>{};
  final retenues = <matrix.Room>[];

  for (final room in rooms) {
    final contact = room.otherUserMxid;
    // Les groupes ne sont pas concernés : plusieurs groupes peuvent
    // légitimement réunir les mêmes personnes.
    if (contact == null) {
      retenues.add(room);
      continue;
    }
    parContact.putIfAbsent(contact, () => []).add(room);
  }

  for (final fils in parContact.values) {
    if (fils.length == 1) {
      retenues.add(fils.first);
      continue;
    }
    final tries = List<matrix.Room>.from(fils)..sort(comparerChatsDirects);
    retenues
      ..add(tries.first)
      ..addAll(tries.skip(1).where((r) => r.porteUnHistorique));
  }

  return retenues;
}

/// Provider pour la liste des rooms archivées
final archivedRoomsProvider = Provider<List<matrix.Room>>((ref) {
  ref.watch(matrixStateNotifierProvider);

  final client = MatrixService.instance.client;
  if (client == null) return [];

  final archivedIds = ArchiveService.instance.archivedRoomIds;

  return client.rooms
      .where(
        (room) =>
            room.membership == matrix.Membership.join &&
            archivedIds.contains(room.id),
      )
      .toList();
});

/// Provider pour les rooms triées par activité
final sortedRoomsProvider = Provider<List<matrix.Room>>((ref) {
  final rooms = ref.watch(roomsProvider);

  final sortedRooms = List<matrix.Room>.from(rooms)
    ..sort((a, b) {
      final aTime = a.lastEvent?.originServerTs ?? DateTime(1970);
      final bTime = b.lastEvent?.originServerTs ?? DateTime(1970);
      return bTime.compareTo(aTime);
    });

  return sortedRooms;
});

/// Provider pour une room spécifique
final roomProvider = Provider.family<matrix.Room?, String>((ref, roomId) {
  final client = ref.watch(matrixClientProvider);
  return client?.getRoomById(roomId);
});

/// Nom d'affichage résolu d'une room.
///
/// Pour un chat direct entre utilisateurs de l'app, le contact est un compte
/// Matrix `@u_<uuid>` sans display name : on résout son vrai nom depuis le
/// profil Supabase (source de vérité des noms), au lieu d'afficher le localpart
/// `u_<uuid>` ou "Conversation". Repli synchrone sur `room.displayName` (nom de
/// room, display name Matrix du contact, puis localpart) tant que le profil
/// charge ou pour les bots (pas de profil Supabase).
/// Profil Supabase du contact d'un tête-à-tête.
@immutable
class ContactProfile {
  const ContactProfile({
    this.name,
    this.avatarUrl,
    this.deleted = false,
  });

  /// Nom du profil Supabase. Null pour un bot (aucun profil attendu) ou un
  /// compte supprimé : l'appelant retombe alors sur `room.displayName`.
  final String? name;

  /// Avatar du profil Supabase. Null -> repli sur l'avatar Matrix de la room.
  final String? avatarUrl;

  /// Le contact est un utilisateur de l'app (mxid `u_<uuid>`) dont le profil
  /// Supabase n'existe plus : compte supprimé. On garde la room (l'historique
  /// reste lisible) mais l'UI doit le signaler.
  final bool deleted;
}

/// Profil du contact d'un tête-à-tête, résolu depuis Supabase à partir de son
/// mxid.
///
/// Keyé par **mxid** et non par roomId, volontairement : la `Room` Matrix est un
/// objet mutable vivant hors du graphe Riverpod. Keyé par roomId, ce provider
/// mémoriserait le résultat calculé au premier build -- souvent avant que les
/// membres de la room ne soient chargés, donc sans contact identifiable -- et ne
/// se recalculerait jamais (la mutation de la Room n'invalide rien). L'appelant
/// lit donc `room.otherUserMxid` à chaque build (toujours frais) et ne délègue
/// ici que la résolution Supabase, dont la clé est stable.
final contactProfileProvider =
    FutureProvider.family<ContactProfile, String>((ref, contactMxid) async {
  final supabaseId =
      ref.watch(matrixServiceProvider).supabaseIdFromMatrixUserId(contactMxid);
  // Pas un mxid d'utilisateur de l'app (bot `@rempart_*`/`@ubot_*`) : aucun
  // profil Supabase attendu, ce n'est pas un compte supprimé.
  if (supabaseId == null) return const ContactProfile();

  final profile = await ref.watch(profileProvider(supabaseId).future);
  // Le mxid dérive bien d'un id Supabase, mais le profil a disparu.
  if (profile == null) return const ContactProfile(deleted: true);

  return ContactProfile(name: profile.name, avatarUrl: profile.avatarUrl);
});

/// Nom d'une conversation tel qu'on le montre à l'utilisateur.
///
/// **Jamais un identifiant.** Un « u_cac4cfdb367a40668f816e51487fb3bf » ne dit
/// rien à personne, et c'est pourtant ce qui s'affichait dans les dialogues :
/// `Room.displayName` retombe sur le localpart quand le nom Matrix du contact
/// n'est pas en mémoire, ce qui est le cas courant au démarrage (l'état des
/// membres n'est pas préchargé, voir `unsafeGetUserFromMemoryOrFallback`).
///
/// L'ordre suit les sources de vérité du projet : le nom de la room si c'est
/// un groupe, puis le profil **Supabase** du contact (référence des noms),
/// puis son profil Matrix (les bots n'ont que celui-là), et en dernier recours
/// un mot neutre plutôt qu'un identifiant.
///
/// Lecture et non observation : les appelants sont des dialogues et des
/// messages ponctuels, pas des widgets qui se reconstruisent. Les deux profils
/// ont déjà été chargés par la liste des conversations, le cache répond donc
/// sans attente.
String nomAffichable(WidgetRef ref, matrix.Room room) {
  if (room.name.isNotEmpty) return room.name;

  final contactMxid = room.otherUserMxid;
  if (contactMxid == null) return 'cette conversation';

  // `nomLisible` et non `displayName` : ce dernier rendrait l'identifiant que
  // l'on cherche justement à ne jamais écrire. Il sert de recours quand les
  // profils n'ont pas encore répondu, car le nom Matrix gardé en mémoire vaut
  // toujours mieux qu'un « ce contact » anonyme.
  return ref.read(nomContactProvider(contactMxid)) ??
      room.nomLisible ??
      'ce contact';
}

/// Nom d'une personne, ou `null` si aucune source ne le donne.
///
/// Profil Supabase d'abord (référence des noms du projet), profil Matrix
/// ensuite (les bots n'ont que celui-là). Le repli est laissé à l'appelant :
/// une phrase se contente de « ce contact », une liste doit encore distinguer
/// ses lignes.
///
/// Un `Provider` et non une fonction : les deux sources sont asynchrones, et
/// le nom doit apparaître de lui-même dès qu'elles répondent.
final nomContactProvider = Provider.family<String?, String>((ref, mxid) {
  final supabase = ref.watch(contactProfileProvider(mxid)).value?.name;
  if (supabase != null && supabase.isNotEmpty) return supabase;

  final matrixNom = ref.watch(matrixProfileProvider(mxid)).value?.displayName;
  if (matrixNom != null && matrixNom.isNotEmpty) return matrixNom;

  return null;
});

/// Profil Matrix d'un utilisateur : nom affiché et avatar tels que le serveur
/// les connaît.
///
/// Repli pour qui n'a pas de profil Supabase (bots `@rempart_*` / `@ubot_*`,
/// compte d'un autre serveur) : sans lui, la fiche d'un bot n'afficherait que
/// son mxid. Le SDK garde ce profil en cache un jour, la fiche reste donc
/// lisible hors ligne.
final matrixProfileProvider =
    FutureProvider.family<matrix.Profile?, String>((ref, mxid) async {
  final client = ref.watch(matrixClientProvider);
  if (client == null) return null;
  try {
    return await client.getProfileFromUserId(mxid);
  } catch (e) {
    // Serveur injoignable et rien en cache : la fiche se contente du mxid.
    debugPrint('matrixProfileProvider: profil indisponible pour $mxid ($e)');
    return null;
  }
});

/// Membres d'une room.
///
/// `requestParticipants` complète au besoin depuis le serveur : la liste des
/// membres n'est pas toujours entière dans la base locale (le sync initial
/// n'envoie que les membres utiles à l'affichage).
final roomMembersProvider =
    FutureProvider.family<List<matrix.User>, String>((ref, roomId) async {
  // Un membre qui rejoint arrive par le sync : sans l'écouter, la liste reste
  // celle du premier affichage (un bot invité n'apparaissait jamais).
  ref
    ..watch(matrixStateNotifierProvider)
    ..watch(syncTickProvider);
  final room = ref.watch(roomProvider(roomId));
  if (room == null) return const [];

  // La base locale suffit dès qu'elle couvre tous les membres joints : on
  // n'interroge le serveur que lorsqu'il en manque, sinon chaque sync
  // déclencherait un aller-retour.
  final locaux = room.getParticipants();
  final joints = room.summary.mJoinedMemberCount ?? locaux.length;
  if (locaux.length >= joints) return locaux;
  return room.requestParticipants();
});

/// Recherche parmi les conversations existantes, par nom du correspondant.
///
/// Le nom cherché est celui que l'utilisateur voit dans la liste : celui du
/// profil Supabase quand il existe, sinon le nom Matrix. Chercher sur le seul
/// `room.displayName` raterait les contacts renommés côté Supabase.
final conversationSearchProvider =
    FutureProvider.family<List<matrix.Room>, String>((ref, query) async {
  final recherche = query.trim().toLowerCase();
  if (recherche.isEmpty) return [];

  final rooms = ref.watch(sortedRoomsProvider);
  final resultats = <matrix.Room>[];
  for (final room in rooms) {
    final contactMxid = room.otherUserMxid;
    var nom = room.displayName;
    if (contactMxid != null) {
      final contact =
          await ref.watch(contactProfileProvider(contactMxid).future);
      final nomSupabase = contact.name;
      if (nomSupabase != null && nomSupabase.isNotEmpty) {
        nom = nomSupabase;
      }
    }
    if (nom.toLowerCase().contains(recherche)) {
      resultats.add(room);
    }
  }
  return resultats;
});

/// Provider pour observer les mises à jour Matrix
final matrixSyncProvider = StreamProvider<matrix.SyncUpdate>((ref) {
  final matrixService = ref.watch(matrixServiceProvider);
  final stream = matrixService.onSync;
  if (stream == null) return const Stream.empty();
  return stream;
});

// ============================================
// Matrix Timeline Providers (Messages)
// ============================================

/// Provider pour la timeline d'une room
final timelineProvider =
    FutureProvider.family<matrix.Timeline?, String>((ref, roomId) async {
  final room = ref.watch(roomProvider(roomId));
  if (room == null) return null;

  return room.getTimeline();
});

/// Provider pour les événements (messages) d'une room
final roomEventsProvider =
    Provider.family<List<matrix.Event>, String>((ref, roomId) {
  final timeline = ref.watch(timelineProvider(roomId)).value;
  if (timeline == null) return [];

  // Filtrer seulement les messages (pas les événements système)
  return timeline.events
      .where(
        (e) =>
            (e.type == matrix.EventTypes.Message ||
                e.type == matrix.EventTypes.Encrypted ||
                e.type == matrix.EventTypes.Sticker) &&
            // Une édition remplace le contenu de sa cible : elle est appliquée
            // à l'affichage (`getDisplayEvent`), jamais listée comme un
            // message à part entière.
            !e.estUneEdition,
      )
      .toList();
});

/// Battement du sync Matrix.
///
/// Les accusés de lecture et l'état de saisie voyagent en événements
/// éphémères, hors timeline : sans ce déclencheur, un écran qui ne dépend que
/// des messages ne se reconstruirait pas et afficherait des coches figées.
final syncTickProvider = StreamProvider<int>((ref) async* {
  final client = ref.watch(matrixClientProvider);
  if (client == null) {
    yield 0;
    return;
  }

  var tick = 0;
  yield tick;
  await for (final _ in client.onSync.stream) {
    yield ++tick;
  }
});

/// Membres en train d'écrire dans une room, hors soi-même.
///
/// La saisie arrive par les événements éphémères du sync, qui ne passent pas
/// par la timeline : ce provider s'adosse donc à `onSync` et non aux messages.
final typingUsersProvider =
    StreamProvider.family<List<String>, String>((ref, roomId) async* {
  final client = ref.watch(matrixClientProvider);
  if (client == null) {
    yield const <String>[];
    return;
  }

  List<String> lire() {
    final room = client.getRoomById(roomId);
    if (room == null) return const [];
    return room.typingUsers
        .where((u) => u.id != client.userID)
        .map((u) => u.calcDisplayname())
        .toList();
  }

  yield lire();
  await for (final _ in client.onSync.stream) {
    yield lire();
  }
});

/// Ce contact est-il en ligne, en suivant les changements et non un instantané.
///
/// La présence n'arrive pas à l'ouverture de l'écran : elle vient du sync,
/// souvent plus tard. Un `FutureBuilder` posait donc la question une fois et
/// n'apprenait jamais qu'un agent venait de se connecter, il fallait sortir de
/// la conversation et y revenir pour voir « En ligne ».
///
/// Le flux du SDK est la seule source qui prévienne : `fetchCurrentPresence`
/// rend d'abord son cache, lequel ne bouge qu'au sync suivant.
final presenceEnLigneProvider =
    StreamProvider.family<bool, String>((ref, mxid) async* {
  final client = ref.watch(matrixClientProvider);
  if (client == null) {
    yield false;
    return;
  }

  // Premier état : ce qu'on sait déjà, sans attendre un changement qui peut
  // ne jamais venir si le contact est en ligne depuis un moment.
  try {
    final connue = await client.fetchCurrentPresence(mxid);
    yield connue.presence == matrix.PresenceType.online;
  } catch (e) {
    debugPrint('presence: état initial de $mxid indisponible ($e)');
    yield false;
  }

  await for (final presence in client.onPresenceChanged.stream) {
    if (presence.userid != mxid) continue;
    yield presence.presence == matrix.PresenceType.online;
  }
});

// ============================================
// State Notifiers pour les actions
// ============================================

/// Dernier événement lu **localement** dans chaque conversation, par room.
///
/// Le compteur de non-lus vient du serveur (`notificationCount`) : il ne
/// retombe à zéro qu'au sync suivant le marqueur de lecture. En revenant
/// aussitôt à la liste, la conversation qu'on vient de lire s'y affichait donc
/// encore en gras, avec sa pastille, comme si l'ouverture n'avait pas compté.
///
/// On retient donc ce qu'on vient de lire, sans attendre le serveur. La clé
/// est l'**identifiant du dernier message lu**, et non un simple drapeau :
/// qu'un nouveau message arrive, et la conversation redevient non lue d'
/// elle-même, sans qu'on ait à penser à effacer quoi que ce soit.
final derniersLusProvider = StateProvider<Map<String, String>>(
  (ref) => const <String, String>{},
);

/// State pour la room sélectionnée
final selectedRoomIdProvider = StateProvider<String?>((ref) => null);

/// State pour le message en cours de réponse
final replyToEventProvider = StateProvider<matrix.Event?>((ref) => null);

/// State pour la recherche de contacts
final contactSearchQueryProvider = StateProvider<String>((ref) => '');

/// State pour l'indicateur "en train d'écrire"
final isTypingProvider =
    StateProvider.family<bool, String>((ref, roomId) => false);

// ============================================
// Matrix Connection State
// ============================================

/// Notifier pour forcer le rafraîchissement de l'état Matrix
final matrixStateNotifierProvider = StateProvider<int>((ref) => 0);

/// Provider pour l'état de connexion Matrix
final matrixConnectionStateProvider = Provider<bool>((ref) {
  // Écouter le notifier pour se rafraîchir quand on l'incrémente
  ref.watch(matrixStateNotifierProvider);
  final matrixService = ref.watch(matrixServiceProvider);
  return matrixService.isLoggedIn;
});

/// Vrai quand la synchronisation avec le serveur échoue.
///
/// À ne pas confondre avec [matrixConnectionStateProvider], qui dit seulement
/// qu'une session existe : il reste vrai hors ligne, et affichait donc
/// « Actif » alors que plus rien n'arrivait. Ici on suit l'état réel de la
/// boucle de sync, seule à savoir si le serveur répond.
///
/// `waitingForResponse` est l'état normal du long-poll, pas une panne : seul
/// `error` compte.
final horsLigneProvider = StreamProvider<bool>((ref) async* {
  ref.watch(matrixStateNotifierProvider);
  final client = ref.watch(matrixClientProvider);
  if (client == null) {
    yield false;
    return;
  }
  yield client.onSyncStatus.value?.status == matrix.SyncStatus.error;
  await for (final maj in client.onSyncStatus.stream) {
    yield maj.status == matrix.SyncStatus.error;
  }
});

/// Provider pour l'état d'initialisation Matrix
final matrixInitializedProvider = Provider<bool>((ref) {
  ref.watch(matrixStateNotifierProvider);
  final matrixService = ref.watch(matrixServiceProvider);
  return matrixService.isInitialized;
});


// ===========================================================================
// Inscription ouverte ou non : la reponse vient du SERVEUR
// ===========================================================================

/// Vrai quand le serveur accepte de nouvelles inscriptions.
///
/// La reponse n'est pas un reglage de l'application mais un drapeau de GoTrue
/// (`DISABLE_SIGNUP`), republie par `/auth/v1/settings`. C'est ce qui rend la
/// fermeture **reversible sans rien republier** : on remet le drapeau a false
/// sur le serveur, on redemarre `auth`, et l'application rouvre d'elle-meme.
/// Un drapeau cote application aurait exige un nouveau build, donc une
/// nouvelle publication sur les magasins, pour un simple changement de date.
///
/// En cas de panne reseau on repond **ouvert** : mieux vaut un formulaire qui
/// echoue en disant pourquoi qu'un ecran « bientot disponible » affiche a tort
/// alors que le service fonctionne.
final inscriptionOuverteProvider = FutureProvider<bool>((ref) async {
  if (SupabaseConstants.url.isEmpty) return true;
  try {
    final reponse = await http.get(
      Uri.parse('${SupabaseConstants.url}/auth/v1/settings'),
      headers: {'apikey': SupabaseConstants.anonKey},
    ).timeout(const Duration(seconds: 6));
    if (reponse.statusCode != 200) return true;
    final corps = jsonDecode(reponse.body) as Map<String, dynamic>;
    return corps['disable_signup'] != true;
  } catch (_) {
    return true;
  }
});
