import 'package:matrix/matrix.dart';

import '../../core/utils/secret_message.dart';

/// Extensions pour Room (équivalent de Conversation)
/// Localpart d'un identifiant Matrix (`@nom:serveur` -> `nom`).
String? _extractLocalpart(String matrixId) {
  if (matrixId.startsWith('@') && matrixId.contains(':')) {
    return matrixId.substring(1, matrixId.indexOf(':'));
  }
  return null;
}

extension RoomHelpers on Room {
  /// Nombre de messages non lus
  int get unreadCount => notificationCount;

  /// mxid du contact pour un tête-à-tête.
  ///
  /// Ne se limite pas à `directChatMatrixID` (qui dépend de l'account data
  /// `m.direct`, absente côté invité quand l'invitation a été auto-rejointe) :
  /// retombe sur les `heroes` d'une room sans nom à deux participants, puis sur
  /// les membres. Renvoie null pour un groupe.
  String? get otherUserMxid {
    // Une room portant un nom est un groupe : son titre et son avatar sont ceux
    // de la room, jamais ceux d'un participant. Sans ce garde-fou, un groupe à
    // deux prendrait le nom et l'avatar du contact (il est alors son unique
    // « hero »).
    if (name.isNotEmpty) return null;

    final direct = directChatMatrixID;
    if (direct != null) return direct;
    final heroes = summary.mHeroes;
    if (heroes != null && heroes.length == 1) return heroes.first;
    final others = getParticipants()
        .map((u) => u.id)
        .where((id) => id != client.userID)
        .toSet();
    return others.length == 1 ? others.first : null;
  }

  /// Obtient le titre de la room
  /// Pour les DM, retourne le nom de l'autre participant
  ///
  /// Repli synchrone : nom explicite de room, sinon display name Matrix du
  /// contact (renseigné pour les bots), sinon localpart. La résolution du nom
  /// depuis le profil Supabase (source de vérité des noms) se fait côté UI via
  /// `roomDisplayNameProvider`.
  String get displayName {
    if (name.isNotEmpty) return name;
    final contactMxid = otherUserMxid;
    if (contactMxid != null) {
      final memberName =
          unsafeGetUserFromMemoryOrFallback(contactMxid).displayName;
      if (memberName != null && memberName.isNotEmpty) return memberName;
      return _extractLocalpart(contactMxid) ?? contactMxid;
    }
    return 'Conversation';
  }

  /// Nom que la room sait donner d'elle-même, ou `null` si ce n'en est pas un.
  ///
  /// [displayName] retombe sur le localpart du contact faute de mieux : c'est
  /// commode pour trier ou tirer une initiale, illisible dès qu'on l'écrit
  /// dans une phrase (« u_cac4cfdb367a40668f816e51487fb3bf conservera le
  /// fil »). Ce getter écarte ce repli au lieu de le propager, et laisse
  /// l'appelant choisir quoi dire à la place.
  String? get nomLisible {
    final nom = displayName;
    final contactMxid = otherUserMxid;
    if (contactMxid == null) return nom;
    return estUnIdentifiant(nom, contactMxid) ? null : nom;
  }

  /// Obtient l'URL de l'avatar
  Uri? get avatarUri => avatar;

  /// Le dernier événement est-il un message qu'on ne saura pas lire ?
  ///
  /// Ce cas vient presque toujours de l'historique d'avant notre arrivée dans
  /// un groupe : la clé de session n'a jamais été partagée avec nous et ne le
  /// sera jamais. Le fil de discussion masque ces messages, la liste ne doit
  /// donc pas les annoncer : une conversation affichée « Aucun message » ne
  /// peut pas s'accompagner d'un « Message chiffré · Hier » dans l'aperçu.
  ///
  /// Cacher la ligne est aussi le bon parti dans l'autre cas de figure, plus
  /// rare, où la clé nous manque encore alors qu'elle nous est destinée : le
  /// SDK redéchiffre l'événement dès qu'elle arrive, et l'aperçu revient de
  /// lui-même. Le tri, lui, s'appuie sur `lastEvent` sans passer par ici et
  /// garde la conversation à sa place.
  bool get _dernierMessageIllisible =>
      lastEvent?.messageType == MessageTypes.BadEncrypted;

  /// Obtient le dernier message sous forme de texte
  String get lastMessageText {
    final lastEvent = this.lastEvent;
    if (lastEvent == null || _dernierMessageIllisible) return '';

    switch (lastEvent.type) {
      case EventTypes.Message:
        // `plaintextBody` rend « Redacted », en anglais, pour un message
        // effacé : la bulle dit « Message supprimé », l'aperçu doit s'accorder.
        return lastEvent.texteApercu;
      case EventTypes.Encrypted:
        return 'Message chiffré';
      case EventTypes.RoomMember:
        return _getMemberEventText(lastEvent);
      default:
        return '';
    }
  }

  /// Obtient l'heure du dernier message
  DateTime? get lastMessageTime =>
      _dernierMessageIllisible ? null : lastEvent?.originServerTs;

  /// Obtient l'ID du dernier expéditeur
  String? get lastMessageSenderId => lastEvent?.senderId;

  /// La room porte-t-elle un historique de discussion ?
  ///
  /// `lastEvent` est déjà filtré par le SDK sur les types dignes d'un aperçu :
  /// sa présence signale un vrai échange, son absence une room restée vide.
  /// Un dernier message illisible ne compte pas : rien n'en sera montré.
  bool get porteUnHistorique => lastEvent != null && !_dernierMessageIllisible;

  /// Liste des membres de la room
  List<User> get membersList => getParticipants();

  /// Nombre de membres
  int get memberCount => summary.mJoinedMemberCount ?? 1;

  String _getMemberEventText(Event event) {
    final membership = event.content['membership'] as String?;
    final displayName =
        _extractLocalpart(event.stateKey ?? '') ?? 'Utilisateur';

    switch (membership) {
      case 'join':
        return '$displayName a rejoint';
      case 'leave':
        return '$displayName a quitté';
      case 'invite':
        return '$displayName a été invité';
      case 'ban':
        return '$displayName a été banni';
      default:
        return '';
    }
  }

  /// Extrait le localpart d'un Matrix ID
}

/// Extensions pour Event (équivalent de Message)
extension EventHelpers on Event {
  /// Vérifie si c'est un message texte
  bool get isTextMessage =>
      type == EventTypes.Message &&
      (messageType == MessageTypes.Text || messageType == MessageTypes.Notice);

  /// Vérifie si c'est une image
  bool get isImageMessage =>
      type == EventTypes.Message && messageType == MessageTypes.Image;

  /// Vérifie si c'est une vidéo
  bool get isVideoMessage =>
      type == EventTypes.Message && messageType == MessageTypes.Video;

  /// Vérifie si c'est un audio
  bool get isAudioMessage =>
      type == EventTypes.Message && messageType == MessageTypes.Audio;

  /// Vérifie si c'est un fichier
  bool get isFileMessage =>
      type == EventTypes.Message && messageType == MessageTypes.File;

  /// L'événement est lui-même une édition (`m.replace`) visant un message.
  ///
  /// Ces événements ne sont PAS des messages : ils remplacent le contenu de
  /// leur cible. Les afficher tels quels ajoutait une seconde bulle sous
  /// l'originale au lieu de le corriger.
  bool get estUneEdition => relationshipType == RelationshipTypes.edit;

  /// Le message a été modifié après coup, c'est-à-dire qu'au moins une
  /// `m.replace` le vise. Demande la timeline, qui porte les agrégations.
  bool aEteModifie(Timeline timeline) =>
      hasAggregatedEvents(timeline, RelationshipTypes.edit);

  /// Vérifie si le message a été supprimé (redacted)
  bool get isDeleted => redacted;

  /// Le message a-t-il été lu par un autre participant ?
  ///
  /// À ne pas confondre avec `EventStatus.synced`, qui atteste seulement que
  /// le serveur a accepté l'événement : afficher la double coche sur ce
  /// critère annonçait « lu » dès la réception, avant même que le destinataire
  /// n'ouvre la conversation.
  ///
  /// Un accusé Matrix ne désigne que le DERNIER message lu ; les précédents
  /// n'en portent aucun. On compare donc les horodatages plutôt que de
  /// chercher un accusé posé sur cet événement précis.
  bool get luParUnAutre {
    final moi = room.client.userID;
    final etats = [
      room.receiptState.global,
      if (room.receiptState.mainThread != null) room.receiptState.mainThread!,
    ];

    for (final etat in etats) {
      for (final entree in etat.otherUsers.entries) {
        if (entree.key == moi) continue;
        if (!entree.value.timestamp.isBefore(originServerTs)) return true;
      }
    }
    return false;
  }

  /// Vérifie si c'est un message système
  bool get isSystemMessage =>
      type == EventTypes.RoomMember ||
      type == EventTypes.RoomCreate ||
      type == EventTypes.RoomName ||
      type == EventTypes.RoomTopic;

  /// Le message transporte-t-il un fichier ?
  bool get porteUnFichier =>
      isImageMessage || isVideoMessage || isAudioMessage || isFileMessage;

  /// Légende d'une pièce jointe, ou null s'il n'y en a pas.
  ///
  /// Convention Matrix : quand une légende accompagne un fichier, `body` porte
  /// le texte et `filename` le vrai nom. Sans légende, les deux valent le nom
  /// du fichier, et il n'y a donc rien à afficher sous l'image.
  String? get legendePieceJointe {
    final nom = content['filename'];
    if (nom is! String || nom.isEmpty) return null;
    final corps = content['body'];
    if (corps is! String || corps.isEmpty || corps == nom) return null;
    return corps;
  }

  /// Corps mis en forme (`formatted_body`), ou null si le message est en texte
  /// brut.
  ///
  /// Seul le format `org.matrix.custom.html` est reconnu, le seul que la
  /// spécification définisse. Un message sans mise en forme continue de passer
  /// par [displayText], plus léger à rendre.
  String? get corpsFormate {
    if (content['format'] != 'org.matrix.custom.html') return null;
    final corps = content['formatted_body'];
    if (corps is! String || corps.trim().isEmpty) return null;
    return corps;
  }

  /// Nom de l'expéditeur, ou null s'il ne reste qu'un identifiant.
  ///
  /// `calcDisplayname()` retombe sur le localpart quand le profil n'est pas
  /// chargé, ce qui est le cas courant au démarrage et dans un isolate qui
  /// vient de naître. Or « u_cac4cfdb367a... » sur un écran verrouillé ne dit
  /// rien à personne : mieux vaut ne rien nommer que nommer un identifiant.
  String? get nomLisibleDeLExpediteur {
    final nom = senderFromMemoryOrFallback.calcDisplayname();
    if (nom.isEmpty) return null;
    return estUnIdentifiant(nom, senderId) ? null : nom;
  }

  /// Obtient le texte à afficher
  String get displayText {
    if (redacted) return 'Message supprimé';
    return libelleBouton ?? plaintextBody;
  }

  /// Texte du message pour tout affichage **hors de sa bulle** : aperçu de la
  /// liste, citation d'une réponse, barre « répondre à ».
  ///
  /// Le masque « Appuyer pour afficher » ne protège que la bulle. Partout
  /// ailleurs le même corps se lisait en clair, et souvent de plus loin : un
  /// code d'entrée caché dans le fil s'affichait en entier sur la liste des
  /// conversations. Un secret n'est donc jamais recopié hors de sa bulle.
  String get texteApercu {
    final media = libelleMedia;
    if (media != null) return media;
    final texte = displayText;
    return ressembleAUnSecret(texte) ? 'Message masqué' : texte;
  }

  /// Identifiant de l'envoi groupé auquel ce média appartient, ou null.
  ///
  /// Matrix n'a pas d'album : plusieurs photos envoyées ensemble sont autant
  /// de messages distincts, et le fil les empilait un par un sur toute la
  /// hauteur de l'écran. On pose donc une marque à nous, que les autres
  /// clients ignorent sans rien casser : ils affichent alors ce qui est vrai,
  /// une suite de photos.
  String? get albumId {
    final marque = content['fr.rempart.album'];
    if (marque is! Map) return null;
    final id = marque['id'];
    return id is String && id.isNotEmpty ? id : null;
  }

  /// Libellé du bouton qui a produit ce message, ou null.
  ///
  /// Une réponse à un bouton porte la **valeur** dans son corps, parce que
  /// c'est elle que l'agent attend (« !cancel »), et le **libellé** à côté.
  /// L'utilisateur, lui, a appuyé sur « ❌ Annuler » : c'est ce geste qu'il
  /// doit relire dans la conversation, pas une commande qu'il n'a pas tapée.
  ///
  /// Les autres clients Matrix ignorent le champ et affichent la valeur, ce
  /// qui reste juste : c'est bien ce qui a été envoyé.
  String? get libelleBouton {
    final libelle = content['fr.rempart.libelle_bouton'];
    return libelle is String && libelle.trim().isNotEmpty
        ? libelle.trim()
        : null;
  }

  /// Symbole d'une réaction, ou null si l'événement n'en est pas une.
  String? get symboleReaction {
    if (type != EventTypes.Reaction) return null;
    final relation = content['m.relates_to'];
    if (relation is! Map) return null;
    final cle = relation['key'];
    return cle is String && cle.isNotEmpty ? cle : null;
  }

  /// Identifiant du message visé par cette réaction, ou null.
  String? get cibleReaction {
    if (type != EventTypes.Reaction) return null;
    final relation = content['m.relates_to'];
    if (relation is! Map) return null;
    final cible = relation['event_id'];
    return cible is String && cible.isNotEmpty ? cible : null;
  }

  /// Ce qu'on dit d'une pièce jointe hors de sa bulle, ou null si le message
  /// n'en est pas une.
  ///
  /// Le corps d'un média est son **nom de fichier** : la liste des
  /// conversations et les notifications affichaient donc
  /// « vocal_1788625858562.m4a », qui n'apprend rien et occupe toute la ligne.
  /// Une légende, elle, est du texte voulu par l'expéditeur : elle passe avant.
  String? get libelleMedia {
    if (!isImageMessage &&
        !isVideoMessage &&
        !isAudioMessage &&
        !isFileMessage) {
      return null;
    }
    final legende = legendePieceJointe;
    if (legende != null) {
      return ressembleAUnSecret(legende) ? 'Message masqué' : legende;
    }
    if (isAudioMessage) return 'Message vocal';
    if (isImageMessage) return 'Photo';
    if (isVideoMessage) return 'Vidéo';
    return 'Fichier';
  }

  /// Obtient le nom d'affichage de l'expéditeur
  String get senderDisplayName {
    return room.unsafeGetUserFromMemoryOrFallback(senderId).displayName ??
        _extractLocalpart(senderId) ??
        senderId;
  }

  /// Obtient l'avatar de l'expéditeur
  Uri? get senderAvatarUri {
    return room.unsafeGetUserFromMemoryOrFallback(senderId).avatarUrl;
  }

  /// Vérifie si c'est mon message
  bool isMine(String currentUserId) => senderId == currentUserId;

  /// Vérifie si c'est une réponse
  /// Ce message répond-il à un autre ?
  ///
  /// Une réponse Matrix ne porte **pas** de `rel_type`, contrairement à une
  /// édition, une réaction ou un fil : l'identifiant visé est niché dans
  /// `m.relates_to.m.in_reply_to.event_id`. Lire `relationshipType` rendait
  /// donc toujours null, `isReply` toujours faux, et la citation n'apparaissait
  /// jamais au-dessus de la réponse. Le SDK le dit lui-même : « For replies
  /// please use `Event.inReplyToEventId()` instead ».
  ///
  /// `includingFallback: false` écarte la fausse réponse que le protocole
  /// glisse dans un fil pour les clients qui ne le comprennent pas : ce n'est
  /// pas une citation voulue, et l'afficher serait mentir.
  bool get isReply => inReplyToEventId(includingFallback: false) != null;

  /// Obtient l'événement auquel ce message répond (sans timeline)
  Future<Event?> fetchReplyEvent() async {
    final cible = inReplyToEventId(includingFallback: false);
    if (cible == null) return null;
    return room.getEventById(cible);
  }

  /// Obtient les informations du fichier attaché
  MatrixFileInfo? get fileInfo {
    if (!isImageMessage &&
        !isVideoMessage &&
        !isAudioMessage &&
        !isFileMessage) {
      return null;
    }

    final info = content['info'] as Map<String, dynamic>?;
    if (info == null) return null;

    return MatrixFileInfo(
      fileName: content['body'] as String? ?? 'fichier',
      mimeType: info['mimetype'] as String?,
      size: info['size'] as int?,
      width: info['w'] as int?,
      height: info['h'] as int?,
      duration: info['duration'] as int?,
      thumbnailUrl: info['thumbnail_url'] as String?,
    );
  }

  /// URL du fichier attaché (si disponible)
  Uri? get attachmentUrl {
    final url = content['url'] as String?;
    if (url == null) return null;
    return Uri.tryParse(url);
  }

  /// Télécharge et retourne l'URL HTTP du fichier
  Future<Uri?> getAttachmentHttpUrl() async {
    final mxcUrl = attachmentUrl;
    if (mxcUrl == null) return null;
    return mxcUrl.getDownloadUri(room.client);
  }

  /// Extrait le localpart d'un Matrix ID
}

/// Informations sur un fichier attaché
class MatrixFileInfo {
  const MatrixFileInfo({
    required this.fileName,
    this.mimeType,
    this.size,
    this.width,
    this.height,
    this.duration,
    this.thumbnailUrl,
  });

  final String fileName;
  final String? mimeType;
  final int? size;
  final int? width;
  final int? height;
  final int? duration;
  final String? thumbnailUrl;

  /// Vérifie si c'est une image
  bool get isImage => mimeType?.startsWith('image/') ?? false;

  /// Vérifie si c'est une vidéo
  bool get isVideo => mimeType?.startsWith('video/') ?? false;

  /// Vérifie si c'est un audio
  bool get isAudio => mimeType?.startsWith('audio/') ?? false;

  /// Taille formatée (ex: "2.5 MB")
  String get formattedSize {
    if (size == null) return '';
    if (size! < 1024) return '$size B';
    if (size! < 1024 * 1024) return '${(size! / 1024).toStringAsFixed(1)} KB';
    if (size! < 1024 * 1024 * 1024) {
      return '${(size! / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size! / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Durée formatée (pour audio/vidéo)
  String get formattedDuration {
    if (duration == null) return '';
    final seconds = duration! ~/ 1000;
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}

/// Extensions pour User Matrix
extension UserHelpers on User {
  /// Nom d'affichage ou ID local
  String get name => displayName ?? _extractLocalpart(id) ?? id;

  /// URL de l'avatar HTTP
  Future<Uri?> avatarHttpUrl(Client client) async {
    if (avatarUrl == null) return null;
    return avatarUrl!.getThumbnailUri(
      client,
      width: 256,
      height: 256,
    );
  }

  /// Vérifie si l'utilisateur est en ligne
  Future<bool> isOnlineAsync(Client client) async {
    try {
      final presence = await client.fetchCurrentPresence(id);
      return presence.presence == PresenceType.online;
    } catch (e) {
      return false;
    }
  }

  /// Extrait le localpart d'un Matrix ID
}

/// Classe utilitaire pour les Matrix IDs
class MatrixIdHelper {
  /// Extrait le localpart d'un Matrix ID (@user:domain.com -> user)
  static String? extractLocalpart(String matrixId) {
    if (matrixId.startsWith('@') && matrixId.contains(':')) {
      return matrixId.substring(1, matrixId.indexOf(':'));
    }
    return null;
  }

  /// Extrait le domaine d'un Matrix ID (@user:domain.com -> domain.com)
  static String? extractDomain(String matrixId) {
    if (matrixId.contains(':')) {
      return matrixId.substring(matrixId.indexOf(':') + 1);
    }
    return null;
  }

  /// Crée un Matrix ID complet à partir d'un localpart et domaine
  static String createUserId(String localpart, String domain) {
    return '@$localpart:$domain';
  }
}

/// Ordre de préférence entre deux tête-à-tête ouverts avec le même contact.
///
/// Matrix autorise plusieurs rooms directes entre deux personnes : si chacune
/// ouvre la conversation avant d'avoir vu l'invitation de l'autre, deux rooms
/// coexistent, également valides. Il faut donc en désigner une, et surtout
/// toujours la même, faute de quoi l'app écrirait dans l'une et afficherait
/// l'autre.
///
/// Critères, dans l'ordre : l'historique d'abord (un fil qui contient des
/// messages ne se remplace pas par un fil vide), puis l'activité la plus
/// récente, enfin l'identifiant comme départage stable.
/// Localpart engendré par l'app plutôt que choisi : `u_<uuid Supabase>` pour
/// une personne, `ubot_<hex>` pour un bot créé sans nom demandé.
final _localpartEngendre = RegExp(r'^u(bot)?_[0-9a-f]{6,}$');

/// Le texte proposé n'est-il que l'identifiant du contact, déguisé ?
///
/// `Room.displayName` retombe sur le localpart quand aucun nom n'est connu, et
/// pour un compte Rempart ce localpart est dérivé de l'identifiant Supabase :
/// personne ne s'y reconnaît.
///
/// Un bot, lui, s'appelle vraiment « hermes_bot » : son nom EST son localpart,
/// et l'écarter le priverait du seul nom qu'il ait. D'où le test sur la forme
/// engendrée, et non sur la simple égalité avec le localpart.
bool estUnIdentifiant(String texte, String mxid) {
  if (texte == mxid) return true;
  if (texte != _extractLocalpart(mxid)) return false;
  return _localpartEngendre.hasMatch(texte);
}

/// Le contact est-il encore atteignable dans un tête-à-tête ?
///
/// Notre propre appartenance ne suffit pas à juger : une room que le contact a
/// quittée nous reste, avec tout son historique, et rien ne la distingue à
/// l'oeil d'une conversation vivante. Ce qu'on y écrit ne parvient pourtant à
/// personne, sans le moindre signe, et l'expéditeur croit ses messages
/// délivrés.
///
/// Le doute profite à la room : `null` (état inconnu, serveur injoignable)
/// répond oui, car écarter un fil sain fabriquerait un doublon à chaque
/// tentative, alors qu'une méconnaissance passagère ne prouve aucun départ.
bool contactAtteignable(Membership? membership) =>
    membership == null ||
    membership == Membership.join ||
    membership == Membership.invite;

int comparerChatsDirects(Room a, Room b) {
  final histoireA = a.porteUnHistorique;
  if (histoireA != b.porteUnHistorique) return histoireA ? -1 : 1;

  final dateA = a.lastEvent?.originServerTs;
  final dateB = b.lastEvent?.originServerTs;
  if (dateA != null && dateB != null && dateA != dateB) {
    return dateB.compareTo(dateA);
  }

  return a.id.compareTo(b.id);
}
