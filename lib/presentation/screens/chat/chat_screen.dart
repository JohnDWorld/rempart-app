import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:path_provider/path_provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme.dart';
import '../../../core/mouvement.dart';
import '../../../core/plateforme.dart';
import '../../../core/utils/groupe_album.dart';
import '../../../data/models/bot.dart';
import '../../../data/models/matrix_extensions.dart';
import '../../../data/providers/providers.dart';
import '../../../data/services/compression_image.dart';
import '../../../data/services/enregistreur_vocal.dart';
import '../../../data/services/notification_service.dart';
import '../../../data/services/reinitialisation_e2e.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/chat/glisser_pour_repondre.dart';
import '../../widgets/chat/message_bubble.dart';
import '../../widgets/chat/message_input.dart';
import '../../widgets/chat/selection_texte.dart';
import '../../widgets/chat/visionneuse_image.dart';
import '../../widgets/common/deleted_account_badge.dart';
import '../../widgets/common/encryption_badge.dart';
import '../../widgets/common/fond_rempart.dart';
import '../../widgets/common/user_avatar.dart';

/// Origine d'une pièce jointe proposée à l'utilisateur.
enum _SourcePieceJointe { galerie, camera, video, fichier }

/// Écran de chat pour une room Matrix
/// Largeur au-delà de laquelle le fil cesse de s'étirer et se centre.
///
/// Un écran de bureau n'est pas un grand téléphone : au-delà, on ne gagne
/// plus rien à écarter les bulles, on ne fait que forcer l'oeil à traverser
/// la fenêtre pour suivre un échange. Le reste de l'écran sert déjà, c'est la
/// liste des conversations à gauche.
const _largeurMaxFil = 1100.0;

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    required this.conversationId,
    this.enPanneau = false,
    super.key,
  });

  final String conversationId;

  /// Vrai quand l'écran occupe le panneau de droite, à côté de la liste, et
  /// non toute la fenêtre : le retour ferme alors la conversation au lieu de
  /// naviguer vers un accueil déjà affiché, où le bouton semblerait mort.
  final bool enPanneau;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  // Scroll par index (et non par offset) : sauter à un message depuis la
  // recherche exige de viser sa position, or les bulles ont des hauteurs
  // variables et ne sont construites qu'à l'approche de l'écran.
  final _itemScrollController = ItemScrollController();
  // Les positions visibles disent quand on approche des messages anciens,
  // seul moment où il faut aller en chercher davantage.
  final _itemPositionsListener = ItemPositionsListener.create();
  final _searchController = TextEditingController();
  matrix.Event? _replyTo;
  matrix.Timeline? _timeline;

  /// Vrai pendant une demande d'historique, pour ne pas en lancer dix.
  bool _chargementHistorique = false;

  /// Dernier événement pour lequel un accusé de lecture est parti.
  ///
  /// La timeline notifie très souvent ; sans ce garde, chaque frappe et chaque
  /// reçu déclencherait un aller-retour réseau de plus.
  String? _dernierLu;

  /// Recherche dans la conversation : la barre du haut devient un champ de
  /// saisie et la liste n'affiche plus que les messages correspondants.
  bool _isSearching = false;
  String _searchQuery = '';

  /// Message visé par le dernier saut depuis la recherche, mis en évidence le
  /// temps que l'œil le retrouve dans le fil.
  String? _highlightedEventId;
  Timer? _highlightTimer;

  /// Envoi de pièce jointe en cours (upload + chiffrement peuvent durer).
  bool _envoiPieceJointe = false;

  @override
  void initState() {
    super.initState();
    // Pas de notification pour la conversation qu'on est en train de lire.
    NotificationService.instance.roomOuverte = widget.conversationId;
    _itemPositionsListener.itemPositions.addListener(_surDefilement);
    _initTimeline();
  }

  @override
  void dispose() {
    if (NotificationService.instance.roomOuverte == widget.conversationId) {
      NotificationService.instance.roomOuverte = null;
    }
    _itemPositionsListener.itemPositions.removeListener(_surDefilement);
    _highlightTimer?.cancel();
    _searchController.dispose();
    _timeline?.cancelSubscriptions();
    super.dispose();
  }

  void _ouvrirRecherche() {
    setState(() => _isSearching = true);
  }

  void _fermerRecherche() {
    _searchController.clear();
    setState(() {
      _isSearching = false;
      _searchQuery = '';
    });
  }

  /// Messages affichables de la conversation (hors événements système).
  ///
  /// Les éditions (`m.replace`) sont écartées : elles ne sont pas des messages
  /// mais le nouveau contenu d'un message existant, appliqué au rendu par
  /// `getDisplayEvent`. Les laisser passer affichait une bulle de plus.
  List<matrix.Event> _messages() {
    final rejointLe = _rejointLe();
    return _timeline?.events
            .where(
              (e) =>
                  (e.type == matrix.EventTypes.Message ||
                      e.type == matrix.EventTypes.Encrypted ||
                      e.type == matrix.EventTypes.Sticker) &&
                  !e.estUneEdition &&
                  !_illisibleAvantArrivee(e, rejointLe),
            )
            .toList() ??
        [];
  }

  /// Instant où l'on a rejoint la conversation, ou `null` si l'événement
  /// d'arrivée n'est pas dans l'historique chargé.
  ///
  /// On le cherche dans la timeline et non dans l'état de la room : le SDK
  /// range les événements de membre à part (`_roomMembersBox`) et `postLoad`
  /// ne les remonte pas, si bien que `getState(RoomMember, moi)` est vide au
  /// démarrage. Ce n'est pas gênant : tant qu'on n'a pas remonté jusqu'à son
  /// arrivée, on n'a pas non plus atteint les messages d'avant.
  ///
  /// Un changement de nom ou d'avatar réécrit lui aussi l'événement de membre,
  /// d'où le test sur l'état précédent : seule une vraie arrivée compte.
  DateTime? _rejointLe() {
    final timeline = _timeline;
    final moi = timeline?.room.client.userID;
    if (timeline == null || moi == null) return null;
    // La timeline va du plus récent au plus ancien : la première arrivée
    // rencontrée est la dernière en date, celle qui vaut.
    for (final event in timeline.events) {
      if (event.type == matrix.EventTypes.RoomMember &&
          event.stateKey == moi &&
          event.content['membership'] == 'join' &&
          event.prevContent?['membership'] != 'join') {
        return event.originServerTs;
      }
    }
    return null;
  }

  /// Vrai pour un message chiffré qu'on ne saura jamais lire, et dont on sait
  /// pourquoi.
  ///
  /// Deux coupures, de même nature :
  ///
  /// - **avant notre arrivée** dans la conversation : la clé de session n'a
  ///   jamais été partagée avec nous et ne le sera jamais ;
  /// - **avant une réinitialisation du coffre sans clé de récupération** : les
  ///   clés d'alors n'existent plus nulle part.
  ///
  /// Dans les deux cas, empiler ces bulles n'apprend rien et se lit comme une
  /// panne. On ne masque que celles-là : un échec de déchiffrement postérieur,
  /// lui, signale un vrai problème de clés et doit rester visible.
  bool _illisibleAvantArrivee(matrix.Event event, DateTime? rejointLe) {
    if (event.messageType != matrix.MessageTypes.BadEncrypted) return false;
    if (ReinitialisationE2e.avantLaCoupure(event.originServerTs)) return true;
    return rejointLe != null && event.originServerTs.isBefore(rejointLe);
  }

  /// Texte réellement à l'écran pour un événement : le corps d'origine avec
  /// ses modifications appliquées.
  ///
  /// La liste ne contient que les messages d'origine (les `m.replace` en sont
  /// filtrées), donc sans cette résolution on manipulerait la version d'avant
  /// correction : copier, rechercher et rouvrir l'édition doivent tous porter
  /// sur le texte affiché.
  String _texteAffiche(matrix.Event event) {
    final timeline = _timeline;
    return (timeline == null ? event : event.getDisplayEvent(timeline))
        .plaintextBody;
  }

  /// Ne garde que les messages contenant la recherche. On filtre sur
  /// `plaintextBody` (corps déchiffré, celui qu'affiche la bulle) : chercher
  /// dans `body` raterait tout message chiffré.
  List<matrix.Event> _filtrerRecherche(List<matrix.Event> events) {
    final recherche = _searchQuery.trim().toLowerCase();
    if (recherche.isEmpty) return events;
    // Chercher dans le texte réellement affiché : après une modification,
    // c'est le nouveau libellé que l'utilisateur a sous les yeux et donc
    // celui qu'il retape.
    return events
        .where((e) => _texteAffiche(e).toLowerCase().contains(recherche))
        .toList();
  }

  /// Quitte la recherche et replace le message choisi dans son contexte.
  Future<void> _sauterAuMessage(matrix.Event event) =>
      _sauterAId(event.eventId);

  /// Remonte au message cité, en chargeant l'historique s'il le faut.
  ///
  /// Branché sur la citation affichée au-dessus d'une réponse : c'est le seul
  /// chemin pour retrouver ce à quoi on répondait, une conversation active
  /// repoussant vite l'original hors de l'écran.
  ///
  /// Le chargement est la moitié qui compte : seuls les derniers messages sont
  /// en mémoire à l'ouverture, donc citer un message d'hier vise presque
  /// toujours un événement absent de la liste. Sans la boucle ci-dessous,
  /// l'appui ne ferait rien, ce qui se lit comme une panne.
  Future<void> _remonterALaCitation(matrix.Event reponse) async {
    final vise = reponse.inReplyToEventId(includingFallback: false);
    if (vise == null) return;

    for (var essai = 0; essai < 10; essai++) {
      if (_messages().any((e) => e.eventId == vise)) {
        await _sauterAId(vise);
        return;
      }
      final avant = _timeline?.events.length ?? 0;
      await _chargerPlusHistorique();
      if (!mounted) return;
      // Rien de nouveau : soit le début de la conversation est atteint, soit
      // un chargement déclenché par le défilement tient déjà la place. Dans
      // les deux cas, insister ne donnerait rien de plus.
      if ((_timeline?.events.length ?? 0) == avant) break;
    }

    // Se taire laisserait croire à un appui non pris en compte.
    _signaler('Message introuvable, trop loin dans la conversation');
  }

  Future<void> _sauterAId(String eventId) async {
    // L'index est celui du fil complet, pas de la liste filtrée.
    final index = _messages().indexWhere((e) => e.eventId == eventId);
    _fermerRecherche();
    if (index < 0) return;

    // Sortir de la recherche reconstruit la liste : sans attendre la frame,
    // le scroll viserait encore l'ancienne (celle des résultats).
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_itemScrollController.isAttached) return;

    // Un peu au-dessus du bord : le message atterrit dans la zone lisible,
    // avec ce qui l'entoure. Sans animations, on y saute au lieu d'y glisser.
    if (animationsReduites(context)) {
      _itemScrollController.jumpTo(index: index, alignment: 0.35);
      return;
    }
    await _itemScrollController.scrollTo(
      index: index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      alignment: 0.35,
    );
    _mettreEnEvidence(eventId);
  }

  void _mettreEnEvidence(String eventId) {
    _highlightTimer?.cancel();
    setState(() => _highlightedEventId = eventId);
    _highlightTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _highlightedEventId = null);
      }
    });
  }

  /// Pose l'accusé de lecture sur le dernier message réellement affiché.
  ///
  /// `room.lastEvent` ne convient pas : la sync le laisse parfois vide, ou sur
  /// un événement de remplacement le temps qu'elle le rafraîchisse. L'accusé
  /// partait alors sur un identifiant que le serveur refuse, et comme l'appel
  /// n'était pas attendu, l'erreur disparaissait sans trace : les messages
  /// restaient comptés non lus alors que la conversation était ouverte.
  ///
  /// On prend donc le dernier événement synchronisé de la timeline, celui que
  /// l'utilisateur a sous les yeux.
  Future<void> _marquerCommeLu() async {
    final timeline = _timeline;
    final room = ref.read(roomProvider(widget.conversationId));
    if (timeline == null || room == null) return;

    // La timeline va du plus récent au plus ancien. Un message en cours
    // d'envoi porte un identifiant local, que le serveur ne connaît pas.
    matrix.Event? dernier;
    for (final event in timeline.events) {
      if (event.eventId.startsWith(r'$') &&
          (event.status == matrix.EventStatus.synced ||
              event.status == matrix.EventStatus.sent)) {
        dernier = event;
        break;
      }
    }
    if (dernier == null || dernier.eventId == _dernierLu) return;

    _dernierLu = dernier.eventId;
    // Retenu tout de suite, sans attendre le serveur : `notificationCount` ne
    // retombe qu'au sync suivant, et la liste affichait donc encore en gras
    // la conversation qu'on vient de lire.
    final id = dernier.eventId;
    ref.read(derniersLusProvider.notifier).update(
          (etat) => {...etat, widget.conversationId: id},
        );
    // La liste vit hors du graphe Riverpod : sans ce coup de semonce, elle ne
    // se reconstruirait qu'au prochain événement.
    ref.read(matrixStateNotifierProvider.notifier).state++;
    try {
      await room.setReadMarker(dernier.eventId, mRead: dernier.eventId);
    } catch (e) {
      // Rejouable au prochain passage plutôt que perdu pour la session.
      _dernierLu = null;
      debugPrint('ChatScreen: marquage lu impossible : $e');
    }
  }

  Future<void> _initTimeline() async {
    final room = ref.read(roomProvider(widget.conversationId));
    debugPrint('ChatScreen: initTimeline for room ${widget.conversationId}');
    debugPrint('ChatScreen: room found = ${room != null}');

    if (room == null) {
      debugPrint('ChatScreen: room is null, cannot load timeline');
      return;
    }

    // Vérifier que l'utilisateur est bien membre de la room
    final membership = room.membership;
    debugPrint('ChatScreen: membership = $membership');
    if (membership != matrix.Membership.join) {
      debugPrint('ChatScreen: user is not a member of this room');
      if (mounted) {
        // Retourner à home si l'utilisateur n'est plus membre
        context.go('/home');
      }
      return;
    }

    try {
      final timeline = await room.getTimeline(
        onUpdate: () {
          if (!mounted) return;
          setState(() {});
          // Un message reçu pendant qu'on lit l'écran doit être marqué lu lui
          // aussi : sans cela il reste compté comme non lu dès qu'on sort.
          unawaited(_marquerCommeLu());
        },
      );

      debugPrint(
          'ChatScreen: timeline loaded, events count = ${timeline.events.length}');

      // Complète la liste des membres : elle alimente les propositions après un
      // « @ », et un bot fraîchement invité n'y figure pas encore.
      unawaited(room.requestParticipants().catchError((Object e) {
        debugPrint('ChatScreen: membres non rafraîchis ($e)');
        return <matrix.User>[];
      }));

      // Charger l'historique si la timeline est vide ou a peu de messages
      if (timeline.events.length < 20) {
        debugPrint('ChatScreen: requesting more history...');
        try {
          await timeline.requestHistory(historyCount: 50);
          debugPrint(
              'ChatScreen: after history request, events count = ${timeline.events.length}');
        } catch (e) {
          debugPrint('ChatScreen: error requesting history: $e');
          // Ignorer l'erreur de chargement d'historique
        }
      }

      if (mounted) {
        setState(() {
          _timeline = timeline;
        });
        unawaited(_marquerCommeLu());
      }
    } catch (e) {
      debugPrint('ChatScreen: error loading timeline: $e');
      if (mounted) {
        context.go('/home');
      }
    }
  }

  Future<void> _sendMessage(String content) async {
    final room = ref.read(roomProvider(widget.conversationId));
    if (room == null) return;

    // parseCommands: false -> un message « /commande » (ex. vers un bot) est
    // envoyé tel quel, sans être intercepté comme commande client Matrix.
    if (_replyTo != null) {
      await room.sendTextEvent(
        content,
        inReplyTo: _replyTo,
        parseCommands: false,
      );
    } else {
      await room.sendTextEvent(content, parseCommands: false);
    }

    setState(() => _replyTo = null);

    // Notifier les providers que l'état a changé (pour mettre à jour lastMessage dans la liste)
    ref.read(matrixStateNotifierProvider.notifier).state++;

    // Scroller vers le bas (liste inversée : le message le plus récent est
    // l'index 0).
    if (mounted && _itemScrollController.isAttached) {
      if (animationsReduites(context)) {
        _itemScrollController.jumpTo(index: 0);
      } else {
        unawaited(
          _itemScrollController.scrollTo(
            index: 0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          ),
        );
      }
    }
  }

  /// Propose une source de pièce jointe, puis envoie le fichier retenu.
  Future<void> _choisirPieceJointe() async {
    if (_envoiPieceJointe) return;

    final source = estIOS
        ? await _demanderSourceCupertino()
        : await _demanderSourceMaterial();
    if (source == null || !mounted) return;

    try {
      final fichiers = await _selectionner(source);
      if (fichiers.isEmpty || !mounted) return;
      // Légende AVANT l'envoi : joindre une image sans pouvoir dire ce qu'on en
      // attend obligeait à écrire un second message, que le destinataire
      // rattachait de tête. C'est aussi là que se décide la qualité.
      final limite = await ref.read(matrixServiceProvider).limiteEnvoi();
      if (!mounted) return;
      final choix = await _demanderLegende(fichiers, limite);
      if (choix == null || !mounted) return;
      await _envoyerPiecesJointes(fichiers, choix);
    } catch (e) {
      _signaler('Impossible de joindre le fichier : $e');
    }
  }

  Future<_SourcePieceJointe?> _demanderSourceMaterial() {
    return feuilleAdaptative<_SourcePieceJointe>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Photos et vidéos'),
              subtitle: const Text('Plusieurs à la fois'),
              onTap: () => Navigator.pop(context, _SourcePieceJointe.galerie),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.pop(context, _SourcePieceJointe.camera),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Filmer une vidéo'),
              onTap: () => Navigator.pop(context, _SourcePieceJointe.video),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('Fichier'),
              onTap: () => Navigator.pop(context, _SourcePieceJointe.fichier),
            ),
          ],
        ),
      ),
    );
  }

  Future<_SourcePieceJointe?> _demanderSourceCupertino() {
    return showCupertinoModalPopup<_SourcePieceJointe>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, _SourcePieceJointe.galerie),
            child: const Text('Photos et vidéos'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, _SourcePieceJointe.camera),
            child: const Text('Prendre une photo'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, _SourcePieceJointe.video),
            child: const Text('Filmer une vidéo'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, _SourcePieceJointe.fichier),
            child: const Text('Fichier'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
      ),
    );
  }

  /// Ouvre le sélecteur correspondant et renvoie le fichier prêt à envoyer.
  ///
  /// `MatrixFile.fromMimeType` choisit seul le bon type d'événement Matrix
  /// (image, vidéo, audio ou fichier) d'après le contenu.
  /// Médias choisis, dans leur qualité d'origine.
  ///
  /// Rien n'est réduit ici : la compression a lieu à l'envoi, et seulement si
  /// l'utilisateur n'a pas demandé « HD ». Comprimer dès la sélection
  /// interdirait ce choix, l'original étant alors déjà perdu.
  Future<List<matrix.MatrixFile>> _selectionner(
    _SourcePieceJointe source,
  ) async {
    final picker = ImagePicker();
    switch (source) {
      case _SourcePieceJointe.galerie:
        // Plusieurs d'un coup : partager quinze photos de vacances une par
        // une n'a aucun sens.
        final choisis = await picker.pickMultipleMedia();
        return _versMatrixFiles(choisis);

      case _SourcePieceJointe.camera:
        final choisi = await picker.pickImage(source: ImageSource.camera);
        return _versMatrixFiles([if (choisi != null) choisi]);

      case _SourcePieceJointe.video:
        final choisi = await picker.pickVideo(source: ImageSource.camera);
        return _versMatrixFiles([if (choisi != null) choisi]);

      case _SourcePieceJointe.fichier:
        // withData : sur mobile les octets ne sont pas chargés par défaut, or
        // le SDK Matrix ne sait envoyer qu'à partir des octets.
        final resultat = await FilePicker.platform.pickFiles(
          withData: true,
          allowMultiple: true,
        );
        return [
          for (final fichier in resultat?.files ?? const <PlatformFile>[])
            if (fichier.bytes != null)
              matrix.MatrixFile.fromMimeType(
                bytes: fichier.bytes!,
                name: fichier.name,
              ),
        ];
    }
  }

  Future<List<matrix.MatrixFile>> _versMatrixFiles(List<XFile> choisis) async {
    return [
      for (final choisi in choisis)
        matrix.MatrixFile.fromMimeType(
          bytes: await choisi.readAsBytes(),
          name: choisi.name,
          mimeType: choisi.mimeType,
        ),
    ];
  }

  /// Aperçu de la pièce jointe et saisie d'une légende.
  ///
  /// Renvoie la légende (éventuellement vide) ou null si l'utilisateur renonce.
  Future<_ChoixEnvoi?> _demanderLegende(
    List<matrix.MatrixFile> fichiers,
    int? limiteEnvoi,
  ) {
    return feuilleAdaptative<_ChoixEnvoi>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _FeuilleLegende(
        fichiers: fichiers,
        limiteEnvoi: limiteEnvoi,
      ),
    );
  }

  /// Envoie le vocal qui vient d'être enregistré.
  ///
  /// Même chemin qu'une pièce jointe : le SDK chiffre le média quand la room
  /// l'est. L'échec est dit, car l'enregistrement est alors perdu et il faut
  /// le refaire.
  Future<void> _envoyerVocal(VocalEnregistre vocal) async {
    if (_envoiPieceJointe) return;
    setState(() => _envoiPieceJointe = true);
    try {
      await ref.read(matrixServiceProvider).envoyerVocal(
            roomId: widget.conversationId,
            octets: vocal.octets,
            secondes: vocal.secondes,
            formeOnde: vocal.formeOnde,
            mimeType: vocal.mimeType,
            nom: vocal.nom,
          );
      ref.read(matrixStateNotifierProvider.notifier).state++;
    } catch (e) {
      _signaler('Message vocal non envoyé : $e');
    } finally {
      if (mounted) setState(() => _envoiPieceJointe = false);
    }
  }

  /// Envoie les médias choisis, l'un après l'autre.
  ///
  /// En série et non en parallèle : le serveur limite la taille et le nombre
  /// d'envois simultanés, et quinze photos lancées ensemble se font refuser en
  /// bloc. L'ordre est aussi celui de la sélection, ce qui compte pour une
  /// suite de photos.
  ///
  /// La légende n'accompagne que le PREMIER : répétée sur chacun, elle
  /// donnerait quinze fois le même texte dans le fil.
  Future<void> _envoyerPiecesJointes(
    List<matrix.MatrixFile> fichiers,
    _ChoixEnvoi choix,
  ) async {
    setState(() => _envoiPieceJointe = true);
    var envoyes = 0;
    // Une marque commune aux médias d'un même envoi, pour que le fil les
    // affiche groupés. Inutile pour un seul : une grille d'une case n'est
    // qu'une image.
    final albumId = fichiers.length > 1
        ? 'alb_${DateTime.now().microsecondsSinceEpoch}'
        : null;
    try {
      for (final fichier in fichiers) {
        final aEnvoyer = choix.hauteQualite ? fichier : await _allege(fichier);
        await ref.read(matrixServiceProvider).sendFile(
              roomId: widget.conversationId,
              file: aEnvoyer,
              caption: envoyes == 0 ? choix.legende : '',
              albumId: albumId,
            );
        envoyes++;
        // La liste des conversations lit le client Matrix hors graphe Riverpod.
        ref.read(matrixStateNotifierProvider.notifier).state++;
      }
    } on matrix.FileTooBigMatrixException catch (e) {
      // Le message du SDK est en anglais et parle d'octets : on dit la même
      // chose dans la langue de l'application.
      final max = CompressionImage.poidsLisible(e.maxFileSize);
      final taille = CompressionImage.poidsLisible(e.actualFileSize);
      _signaler(
        envoyes == 0
            ? 'Trop volumineux : $taille, le serveur accepte $max au plus.'
            : '$envoyes envoyé(s). Le suivant fait $taille, '
                'le serveur accepte $max au plus.',
      );
    } catch (e) {
      // On dit combien sont passés : sur un lot, « échec » seul laisserait
      // croire que rien n'est parti.
      _signaler(
        envoyes == 0
            ? 'Envoi impossible : $e'
            : '$envoyes envoyé(s), puis erreur : $e',
      );
    } finally {
      if (mounted) {
        setState(() => _envoiPieceJointe = false);
      }
    }
  }

  /// Version allégée d'une photo, ou le fichier tel quel si ça n'a pas de sens.
  Future<matrix.MatrixFile> _allege(matrix.MatrixFile fichier) async {
    final octets = await CompressionImage.alleger(
      fichier.bytes,
      fichier.mimeType,
    );
    if (identical(octets, fichier.bytes)) return fichier;
    return matrix.MatrixFile.fromMimeType(
      bytes: octets,
      name: fichier.name,
      mimeType: fichier.mimeType,
    );
  }

  /// Nom de fichier proposé par l'expéditeur, ramené à quelque chose de sûr.
  ///
  /// Il vient d'un tiers : le reprendre tel quel permettrait d'écrire ailleurs
  /// que dans le dossier voulu.
  String _nomSur(matrix.Event event) {
    final brut =
        (event.content['filename'] ?? event.content['body']) as String?;
    final base = (brut ?? '').split(RegExp(r'[/\\]')).last.trim();
    final garde = base.replaceAll(RegExp('[^A-Za-z0-9._ -]'), '').trim();
    if (garde.isEmpty || garde.replaceAll('.', '').isEmpty) {
      return 'piece-jointe-${event.eventId.hashCode.abs()}';
    }
    return garde.length > 80 ? garde.substring(garde.length - 80) : garde;
  }

  /// Récupère et déchiffre la pièce jointe, puis l'écrit dans un fichier
  /// temporaire. Renvoie null en cas d'échec (le message est déjà affiché).
  Future<File?> _fichierTemporaire(matrix.Event event) async {
    try {
      final matrixFile = await event.downloadAndDecryptAttachment();
      final dossier = await getTemporaryDirectory();
      final chemin = '${dossier.path}/${_nomSur(event)}';
      final fichier = File(chemin);
      await fichier.writeAsBytes(matrixFile.bytes);
      return fichier;
    } catch (e) {
      _signaler('Téléchargement impossible : $e');
      return null;
    }
  }

  /// Enregistre la pièce jointe : dans la galerie pour une image ou une vidéo,
  /// via la feuille de partage sinon.
  ///
  /// La galerie n'accepte que les médias ; pour un PDF, seule la feuille
  /// système permet de choisir où le ranger.
  Future<void> _enregistrerPieceJointe(matrix.Event event) async {
    final fichier = await _fichierTemporaire(event);
    if (fichier == null || !mounted) return;

    if (!event.isImageMessage && !event.isVideoMessage) {
      await _partagerFichier(fichier, event);
      return;
    }

    try {
      if (event.isVideoMessage) {
        await Gal.putVideo(fichier.path, album: 'Rempart');
      } else {
        await Gal.putImage(fichier.path, album: 'Rempart');
      }
      _signaler('Enregistré dans la galerie (album Rempart).');
    } on GalException catch (e) {
      // Autorisation refusée le plus souvent : la feuille de partage reste une
      // porte de sortie plutôt qu'un échec sec.
      _signaler('Galerie indisponible (${e.type.name}), partage proposé.');
      if (mounted) await _partagerFichier(fichier, event);
    }
  }

  /// Ouvre une image en plein écran.
  ///
  /// Le déchiffrement passe par la même route que la bulle : on ne peut pas
  /// réutiliser l'image déjà affichée, celle-ci vivant dans un widget enfant.
  Future<void> _ouvrirImage(matrix.Event event) async {
    try {
      final fichier = await event.downloadAndDecryptAttachment();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => VisionneuseImage(
            octets: fichier.bytes,
            event: event,
            onEnregistrer: () => _enregistrerPieceJointe(event),
            onPartager: () => _partagerPieceJointe(event),
          ),
        ),
      );
    } catch (e) {
      _signaler("Impossible d'ouvrir l'image : $e");
    }
  }

  Future<void> _partagerPieceJointe(matrix.Event event) async {
    final fichier = await _fichierTemporaire(event);
    if (fichier == null || !mounted) return;
    await _partagerFichier(fichier, event);
  }

  Future<void> _partagerFichier(File fichier, matrix.Event event) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(fichier.path)],
          text: event.legendePieceJointe,
        ),
      );
    } catch (e) {
      _signaler('Partage impossible : $e');
    }
  }

  void _signaler(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Copie le texte du message dans le presse-papiers.
  ///
  /// On copie `plaintextBody` (corps déchiffré) et non `body` : sur un message
  /// chiffré, ce dernier ne contient pas le texte lisible.
  Future<void> _copierMessage(matrix.Event event) async {
    final texte = _texteAffiche(event);
    if (texte.isEmpty) return;

    await Clipboard.setData(ClipboardData(text: texte));
    if (!mounted) return;

    // Android 13+ affiche déjà sa propre confirmation système de copie.
    if (estIOS) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Message copié'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _setReplyTo(matrix.Event event) {
    setState(() => _replyTo = event);
  }

  void _cancelReply() {
    setState(() => _replyTo = null);
  }

  void _showMessageOptions(matrix.Event event) {
    final currentUserId = ref.read(currentMatrixUserIdProvider);
    final isMine = event.senderId == currentUserId;

    if (estIOS) {
      _showCupertinoMessageOptions(event, isMine);
    } else {
      _showMaterialMessageOptions(event, isMine);
    }
  }

  void _showCupertinoMessageOptions(matrix.Event event, bool isMine) {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        // Même rangée que sur Android : une validation demandée par un agent
        // doit se donner d'un appui, quelle que soit la plateforme.
        message: event.redacted ? null : _rangeeReactions(event),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _setReplyTo(event);
            },
            child: const Text('Répondre'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _copierMessage(event);
            },
            child: const Text('Copier'),
          ),
          if (_texteAffiche(event).trim().isNotEmpty)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(context);
                ouvrirSelectionTexte(context, _texteAffiche(event));
              },
              child: const Text('Sélectionner le texte'),
            ),
          if (event.porteUnFichier) ...[
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(context);
                _enregistrerPieceJointe(event);
              },
              child: const Text('Enregistrer'),
            ),
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(context);
                _partagerPieceJointe(event);
              },
              child: const Text('Partager'),
            ),
          ],
          if (isMine && !event.redacted) ...[
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(context);
                _showEditDialog(event);
              },
              child: const Text('Modifier'),
            ),
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(context);
                _confirmDelete(event);
              },
              child: const Text('Supprimer'),
            ),
          ],
          if (!isMine) ...[
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(context);
                _signalerMessage(event);
              },
              child: const Text('Signaler ce message'),
            ),
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(context);
                _bloquer(event.senderId);
              },
              child: const Text('Bloquer cette personne'),
            ),
          ],
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
      ),
    );
  }

  /// Symboles proposés d'un geste, en tête du menu d'un message.
  ///
  /// ✅ et ❌ n'y sont pas par goût : un agent qui demande une validation
  /// propose précisément ces deux-là, et sans eux il faut lui répondre en
  /// tapant une commande.
  static const _reactionsRapides = ['👍', '❤️', '😂', '😮', '✅', '❌'];

  /// Envoie la valeur d'un bouton proposé par un bot.
  ///
  /// Un message ordinaire, et non une réaction : c'est ce que l'agent attend
  /// quand il écrit « réponds valider ou invalider », et cela reste lisible
  /// dans le fil, où l'on voit ce que l'on a répondu.
  /// Répond à un bouton : la **valeur** part à l'agent, le **libellé**
  /// s'affiche dans la conversation.
  ///
  /// L'agent attend « !cancel » ; l'utilisateur, lui, a appuyé sur
  /// « ❌ Annuler » et doit relire son geste, pas une commande. Les deux
  /// voyagent donc dans le même message : le corps porte la valeur, un champ
  /// à nous porte le libellé. Les autres clients Matrix ne voient que la
  /// valeur, ce qui reste juste.
  Future<void> _repondreAuBouton(String texte, String valeur) async {
    try {
      await ref.read(matrixServiceProvider).repondreParBouton(
            roomId: widget.conversationId,
            valeur: valeur,
            libelle: texte,
          );
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Envoi impossible : $e')),
        );
      }
    }
  }

  Future<void> _reagir(matrix.Event event, String symbole) async {
    try {
      await ref.read(matrixServiceProvider).basculerReaction(
            widget.conversationId,
            event,
            symbole,
            _timeline,
          );
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Réaction impossible : $e')),
        );
      }
    }
  }

  /// Rangée de symboles à poser d'un appui, en tête du menu.
  ///
  /// Le `Material` transparent ne dessine rien : il fournit aux `InkWell` le
  /// support qu'ils exigent. Sur iOS la rangée est posée dans une feuille
  /// Cupertino, qui n'en a pas, et sans lui chaque symbole levait « No
  /// Material widget found » : la rangée s'affichait en bloc d'erreur rouge,
  /// alors qu'elle est la façon de répondre d'un appui à un agent.
  Widget _rangeeReactions(matrix.Event event) {
    return Material(
      type: MaterialType.transparency,
      child: _rangeeReactionsContenu(event),
    );
  }

  Widget _rangeeReactionsContenu(matrix.Event event) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (final symbole in _reactionsRapides)
            InkWell(
              onTap: () {
                Navigator.pop(context);
                unawaited(_reagir(event, symbole));
              },
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(symbole, style: const TextStyle(fontSize: 26)),
              ),
            ),
        ],
      ),
    );
  }

  void _showMaterialMessageOptions(matrix.Event event, bool isMine) {
    feuilleAdaptative(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!event.redacted) _rangeeReactions(event),
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Répondre'),
              onTap: () {
                Navigator.pop(context);
                _setReplyTo(event);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copier'),
              onTap: () {
                Navigator.pop(context);
                _copierMessage(event);
              },
            ),
            // Pour n'en copier qu'un morceau : « Copier » prend tout, ce qui
            // ne convient pas quand on veut juste une adresse ou une date au
            // milieu d'un long message.
            if (_texteAffiche(event).trim().isNotEmpty)
              ListTile(
                leading: const Icon(Icons.text_fields),
                title: const Text('Sélectionner le texte'),
                onTap: () {
                  Navigator.pop(context);
                  ouvrirSelectionTexte(context, _texteAffiche(event));
                },
              ),
            if (event.porteUnFichier) ...[
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: Text(event.isImageMessage || event.isVideoMessage
                    ? 'Enregistrer dans la galerie'
                    : 'Enregistrer'),
                onTap: () {
                  Navigator.pop(context);
                  _enregistrerPieceJointe(event);
                },
              ),
              ListTile(
                leading: Icon(Icons.adaptive.share),
                title: const Text('Partager'),
                onTap: () {
                  Navigator.pop(context);
                  _partagerPieceJointe(event);
                },
              ),
            ],
            if (isMine && !event.redacted) ...[
              // Pas de « Modifier » sur un message qui n'est jamais parti :
              // une édition remplace un événement du serveur, et il n'y en a
              // aucun à remplacer. L'entrée ne pouvait qu'échouer.
              if (event.status.isSent)
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('Modifier'),
                  onTap: () {
                    Navigator.pop(context);
                    _showEditDialog(event);
                  },
                ),
              ListTile(
                leading: Icon(
                  Icons.delete,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  'Supprimer',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDelete(event);
                },
              ),
            ],
            if (!isMine) ...[
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Signaler ce message'),
                onTap: () {
                  Navigator.pop(context);
                  _signalerMessage(event);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.block,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  'Bloquer cette personne',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _bloquer(event.senderId);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Signale un message à l'administrateur du serveur.
  ///
  /// Dans une conversation chiffrée, le serveur ne verra pas le message
  /// signalé : seuls son identifiant, sa room et le motif saisi lui
  /// parviennent. C'est peu, mais c'est tout ce qu'un service qui ne lit pas
  /// les messages peut transmettre, et cela suffit pour agir sur un compte.
  Future<void> _signalerMessage(matrix.Event event) async {
    final controleur = TextEditingController();
    final motif = await showAdaptiveDialog<String>(
      context: context,
      builder: (context) => DialogueAdaptatif(
        title: const Text('Signaler ce message'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Le signalement part à l'équipe de modération. Le message étant "
              'chiffré, elle ne pourra pas le lire : décrivez donc le problème.',
            ),
            const SizedBox(height: RempartTokens.espaceL),
            TextField(
              controller: controleur,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Harcèlement, contenu illicite, usurpation...',
              ),
            ),
          ],
        ),
        actions: [
          ActionDialogue(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ActionDialogue(
            principale: true,
            onPressed: () => Navigator.pop(context, controleur.text.trim()),
            child: const Text('Signaler'),
          ),
        ],
      ),
    );
    controleur.dispose();
    if (motif == null || motif.isEmpty || !mounted) return;

    try {
      await ref.read(matrixServiceProvider).signalerMessage(
            event.room.id,
            event.eventId,
            motif: motif,
          );
      _signaler('Signalement envoyé');
    } catch (e) {
      _signaler('Signalement impossible : $e');
    }
  }

  /// Bloque l'auteur d'un message : ses messages cessent d'arriver et les
  /// tête-à-tête avec lui sont quittés.
  Future<void> _bloquer(String mxid) async {
    final nom = ref.read(matrixServiceProvider).client?.userID == mxid
        ? 'vous-même'
        : _nomDe(mxid);
    final confirme = await showAdaptiveAlert<bool>(
      context: context,
      title: 'Bloquer $nom',
      content: 'Vous ne recevrez plus ses messages et les conversations en '
          'tête-à-tête avec cette personne seront quittées. Vous pourrez la '
          'débloquer depuis les réglages.',
      cancelText: 'Annuler',
      confirmText: 'Bloquer',
      isDestructive: true,
    );
    if (confirme != true || !mounted) return;

    try {
      await ref.read(matrixServiceProvider).bloquerUtilisateur(mxid);
      ref.read(matrixStateNotifierProvider.notifier).state++;
      _signaler('$nom a été bloqué');
    } catch (e) {
      _signaler('Blocage impossible : $e');
    }
  }

  /// Nom affiché d'un participant, jamais son identifiant.
  ///
  /// Le profil Supabase d'abord (référence des noms), puis le nom Matrix
  /// (seul renseigné pour les bots), puis ce que la room garde en mémoire.
  /// En dernier recours un mot neutre : un « u_cac4cfdb367a... » dans
  /// « X a été bloqué » ne veut rien dire pour qui le lit.
  String _nomDe(String mxid) {
    final resolu = ref.read(nomContactProvider(mxid));
    if (resolu != null) return resolu;

    final memoire =
        _timeline?.room.unsafeGetUserFromMemoryOrFallback(mxid).displayName;
    if (memoire != null && memoire.isNotEmpty) return memoire;

    return 'ce contact';
  }

  void _showEditDialog(matrix.Event event) {
    final texteCourant = _texteAffiche(event);
    final controller = TextEditingController(text: texteCourant);

    if (estIOS) {
      showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Modifier le message'),
          content: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: CupertinoTextField(
              controller: controller,
              autofocus: true,
              maxLines: null,
              placeholder: 'Message...',
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            CupertinoDialogAction(
              onPressed: () async {
                final newContent = controller.text.trim();
                if (newContent.isNotEmpty && newContent != texteCourant) {
                  final room = ref.read(roomProvider(widget.conversationId));
                  await room?.sendTextEvent(
                    newContent,
                    editEventId: event.eventId,
                  );
                }
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Modifier'),
            ),
          ],
        ),
      );
    } else {
      showAdaptiveDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Modifier le message'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: null,
            decoration: const InputDecoration(
              hintText: 'Message...',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () async {
                final newContent = controller.text.trim();
                if (newContent.isNotEmpty && newContent != texteCourant) {
                  final room = ref.read(roomProvider(widget.conversationId));
                  await room?.sendTextEvent(
                    newContent,
                    editEventId: event.eventId,
                  );
                }
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Modifier'),
            ),
          ],
        ),
      );
    }
  }

  /// Efface un message, et **dit** quand elle n'y arrive pas.
  ///
  /// L'échec était muet : la demande partait dans le vide depuis un
  /// `onPressed` asynchrone dont personne ne lisait l'issue, et le message
  /// restait à l'écran sans un mot. Un « Supprimer » qui ne supprime pas et
  /// ne s'en explique pas se relit comme une application cassée.
  Future<void> _supprimerMessage(matrix.Event event) async {
    try {
      await ref.read(matrixServiceProvider).supprimerMessage(event);
    } catch (e) {
      _signaler('Suppression impossible : $e');
    }
  }

  void _confirmDelete(matrix.Event event) {
    if (estIOS) {
      showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Supprimer le message'),
          content: const Text(
            'Êtes-vous sûr de vouloir supprimer ce message ?',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(context);
                unawaited(_supprimerMessage(event));
              },
              child: const Text('Supprimer'),
            ),
          ],
        ),
      );
    } else {
      showAdaptiveDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Supprimer le message'),
          content: const Text(
            'Êtes-vous sûr de vouloir supprimer ce message ?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                unawaited(_supprimerMessage(event));
              },
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              child: const Text('Supprimer'),
            ),
          ],
        ),
      );
    }
  }

  /// Va chercher la suite de l'historique quand les messages anciens
  /// approchent du bas de la pile.
  ///
  /// La liste est inversée : plus l'index est grand, plus le message est
  /// ancien. Sans ce déclencheur, la timeline restait figée aux 50 événements
  /// demandés au premier chargement, et remonter plus loin était impossible.
  void _surDefilement() {
    if (_isSearching || _chargementHistorique) return;
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;
    final plusAncienVisible =
        positions.map((p) => p.index).reduce((a, b) => a > b ? a : b);
    if (plusAncienVisible >= _messages().length - 5) {
      unawaited(_chargerPlusHistorique());
    }
  }

  Future<void> _chargerPlusHistorique() async {
    final timeline = _timeline;
    if (timeline == null ||
        _chargementHistorique ||
        !timeline.canRequestHistory) {
      return;
    }
    setState(() => _chargementHistorique = true);
    try {
      await timeline.requestHistory(historyCount: 50);
      debugPrint(
          'ChatScreen: historique chargé, events = ${timeline.events.length}');
    } catch (e) {
      debugPrint("ChatScreen: erreur de chargement d'historique: $e");
    } finally {
      if (mounted) setState(() => _chargementHistorique = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = ref.watch(roomProvider(widget.conversationId));
    final currentUserId = ref.watch(currentMatrixUserIdProvider);
    // Les accusés de lecture n'appartiennent pas à la timeline : sans écouter
    // le sync, les coches resteraient dans l'état où elles ont été peintes.
    ref.watch(syncTickProvider);

    if (room == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Conversation')),
        body: const Center(child: Text('Room non trouvée')),
      );
    }

    // Filtrer les messages (pas les événements système)
    final messages = _messages();

    // En recherche, la liste ne montre que les messages correspondants.
    final events = _isSearching ? _filtrerRecherche(messages) : messages;
    // Les photos d'un même envoi se rassemblent en une bulle. Calculé ici, une
    // fois par construction du fil, et non dans chaque tuile : le groupe d'un
    // message dépend de ses voisins.
    return _buildEcran(room, events, grouperParAlbum(events), currentUserId);
  }

  /// L'écran, identique sur les deux plateformes.
  ///
  /// Voir la note de `ConversationsScreen` : un seul dessin, des interactions
  /// adaptatives. iOS gardait ici une barre de navigation classique et une
  /// saisie collée au bas, sans le fond motivé ni les pastilles flottantes
  /// dessinés par la refonte.
  Widget _buildEcran(
    matrix.Room room,
    List<matrix.Event> events,
    List<List<matrix.Event>> groupes,
    String? currentUserId,
  ) {
    // En-tête flottant : rien ne le pousse, il se pose PAR-DESSUS le fil. On
    // réserve donc sa hauteur en rembourrage de liste, sinon le message le
    // plus récent naît caché dessous.
    final hautSecurite = MediaQuery.paddingOf(context).top;
    final hauteurEntete = hautSecurite +
        RempartTokens.espaceS +
        _hauteurPilule +
        RempartTokens.espaceS +
        _hauteurBandeau +
        RempartTokens.espaceS;

    return Scaffold(
      body: FondRempart(
        child: Stack(
          children: [
            // Sur un écran très large, le fil est centré et borné : sans
            // cela mon message colle au bord droit et la réponse au bord
            // gauche, à un demi-mètre de là. On ne lit plus une conversation
            // mais deux colonnes qui se font face.
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: _largeurMaxFil,
                ),
                child: Column(
                  children: [
                    // Liste des messages
                    Expanded(
                      child: _timeline == null
                          ? const Center(child: CircularProgressIndicator.adaptive())
                          : events.isEmpty
                              ? (_isSearching
                                  ? _buildAucunResultat(context)
                                  : _buildEmptyState(context))
                              : ScrollablePositionedList.builder(
                                  itemScrollController: _itemScrollController,
                                  itemPositionsListener: _itemPositionsListener,
                                  // En recherche, les résultats se lisent du haut (les
                                  // plus récents en premier) ; hors recherche, la
                                  // timeline part du bas.
                                  reverse: !_isSearching,
                                  // Le fil passe sous l'en-tête translucide : on le
                                  // décale d'autant, sinon le message le plus ancien
                                  // naît caché derrière la barre.
                                  padding: EdgeInsets.only(
                                    top: hauteurEntete + RempartTokens.espaceS,
                                    bottom: RempartTokens.espaceS,
                                  ),
                                  itemCount: groupes.length,
                                  itemBuilder: (context, index) {
                                    // Les médias d'un même envoi tiennent dans une seule
                                    // bulle : le premier porte le groupe, les autres
                                    // l'accompagnent.
                                    final groupe = groupes[index];
                                    final event = groupe.first;
                                    final isMine =
                                        event.senderId == currentUserId;

                                    // Afficher l'avatar si le message précédent est d'un autre utilisateur
                                    final showAvatar =
                                        index == groupes.length - 1 ||
                                            groupes[index + 1].first.senderId !=
                                                event.senderId;

                                    final brute = MessageBubble(
                                      event: event,
                                      album: groupe.length > 1 ? groupe : null,
                                      timeline: _timeline,
                                      isMine: isMine,
                                      onReagir: (symbole) =>
                                          _reagir(event, symbole),
                                      onBouton: _repondreAuBouton,
                                      showAvatar: showAvatar,
                                      highlighted:
                                          event.eventId == _highlightedEventId,
                                      // En recherche, toucher un résultat le replace dans
                                      // le fil ; sinon une image s'ouvre en grand.
                                      onTap: _isSearching
                                          ? () => _sauterAuMessage(event)
                                          : (event.isImageMessage
                                              ? () => _ouvrirImage(event)
                                              : null),
                                      onLongPress: () =>
                                          _showMessageOptions(event),
                                      // La citation etait deja tactile, mais le rappel
                                      // n'etait passe nulle part : l'appui ne faisait
                                      // rien.
                                      onReplyTap: () =>
                                          _remonterALaCitation(event),
                                    );

                                    // Glisser vers la droite pour répondre, sauf en
                                    // recherche : on y consulte, on n'y écrit pas.
                                    final bulle = _isSearching
                                        ? brute
                                        : GlisserPourRepondre(
                                            onRepondre: () =>
                                                _setReplyTo(event),
                                            child: brute,
                                          );

                                    // Séparateur de jour. La liste est inversée : le
                                    // message plus ancien est à l'index suivant, et le
                                    // séparateur se place au-dessus de la bulle.
                                    if (_isSearching) return bulle;
                                    final precedent = index == events.length - 1
                                        ? null
                                        : events[index + 1];
                                    final nouveauJour = precedent == null ||
                                        !_memeJour(precedent.originServerTs,
                                            event.originServerTs);
                                    if (!nouveauJour) return bulle;
                                    return Column(
                                      children: [
                                        _SeparateurDate(
                                            date: event.originServerTs),
                                        bulle,
                                      ],
                                    );
                                  },
                                ),
                    ),

                    if (_envoiPieceJointe) _buildBandeauEnvoi(),

                    // Barre de saisie (masquée en recherche : on consulte, on n'écrit pas)
                    if (!_isSearching)
                      MessageInput(
                        onSend: _sendMessage,
                        commandes: _commandesDuBot(room),
                        replyTo: _replyTo,
                        onCancelReply: _cancelReply,
                        onAttachmentPressed: _choisirPieceJointe,
                        onTyping: _signalerSaisie,
                        room: room,
                        onVocal: _envoyerVocal,
                      ),
                  ],
                ),
              ),
            ),
            _voileHaut(hautSecurite),
            _enteteFlottante(room, events, hautSecurite),
          ],
        ),
      ),
    );
  }

  /// Voile dégradé sous la barre d'état, derrière les pastilles.
  ///
  /// Le fil défile sous l'en-tête, c'est voulu. Mais sans ce voile il remonte
  /// aussi jusque dans la barre d'état : sur iPhone, une bulle venait se
  /// télescoper avec l'heure et l'îlot dynamique. Un aplat opaque ferait une
  /// barre, ce que la refonte a précisément retiré ; un dégradé qui s'éteint
  /// juste sous les pastilles suffit à décoller le texte du système.
  Widget _voileHaut(double hautSecurite) {
    final couleurs = Theme.of(context).colorScheme;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: hautSecurite + _hauteurPilule,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                couleurs.surface.withValues(alpha: 0.92),
                couleurs.surface.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// En-tête à la Telegram : des pastilles posées sur le fil, et non une
  /// barre pleine largeur.
  ///
  /// Chaque pastille floute ce qui passe dessous : on continue de voir le
  /// motif et les bulles glisser derrière, ce qu'une barre opaque, même
  /// teintée, ne donne pas.
  Widget _enteteFlottante(
    matrix.Room room,
    List<matrix.Event> events,
    double hautSecurite,
  ) {
    final theme = Theme.of(context);

    // Bornée et centrée comme le fil et la barre de saisie : sur un écran
    // large, l'en-tête courait sinon d'un bord à l'autre de la fenêtre au-dessus
    // d'une conversation qui s'arrêtait à 1100 points, et les trois bandes ne
    // se lisaient plus comme une seule colonne. Même marge de 8 points que la
    // barre de saisie, donc leurs bords coïncident exactement.
    //
    // `Align` et non `Center` : l'en-tête reste collé en haut, et les marges
    // laissées vides de part et d'autre ne captent aucun toucher, le fil
    // dessous continue de défiler.
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _largeurMaxFil),
        child: _enteteBornee(room, events, hautSecurite, theme),
      ),
    );
  }

  Widget _enteteBornee(
    matrix.Room room,
    List<matrix.Event> events,
    double hautSecurite,
    ThemeData theme,
  ) {
    return Padding(
      padding: EdgeInsets.only(
        top: hautSecurite + RempartTokens.espaceS,
        left: RempartTokens.espaceS,
        right: RempartTokens.espaceS,
      ),
      child: Column(
        children: [
          Row(
            children: [
              _Pastille(
                child: IconButton(
                  icon: Icon(iconeRetour),
                  tooltip: 'Retour',
                  onPressed: () {
                    // En recherche, le retour ferme d'abord la recherche.
                    if (_isSearching) {
                      _fermerRecherche();
                      return;
                    }
                    if (widget.enPanneau) {
                      ref.read(selectedRoomIdProvider.notifier).state = null;
                      return;
                    }
                    // `go` et non `pop` : le retour doit ramener à l'accueil
                    // d'où qu'on vienne (notification, lien, liste).
                    context.go('/home');
                  },
                ),
              ),
              const SizedBox(width: RempartTokens.espaceS),
              Expanded(
                child: _Pastille(
                  child: SizedBox(
                    height: _hauteurPilule,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: RempartTokens.espaceM,
                      ),
                      child: _isSearching
                          ? TextField(
                              controller: _searchController,
                              autofocus: true,
                              textInputAction: TextInputAction.search,
                              onChanged: (value) =>
                                  setState(() => _searchQuery = value),
                              decoration: const InputDecoration(
                                hintText: 'Rechercher dans la conversation',
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                filled: false,
                                isCollapsed: true,
                              ),
                            )
                          : _buildAppBarTitle(room, isIOS: false),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: RempartTokens.espaceS),
              if (_isSearching)
                _Pastille(
                  child: IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Fermer la recherche',
                    onPressed: _fermerRecherche,
                  ),
                )
              else ...[
                _Pastille(
                  child: IconButton(
                    icon: const Icon(Icons.search),
                    tooltip: 'Rechercher dans la conversation',
                    onPressed: _ouvrirRecherche,
                  ),
                ),
                const SizedBox(width: RempartTokens.espaceS),
                _Pastille(
                  child: MenuAdaptatif<String>(
                    tooltip: MaterialLocalizations.of(context).showMenuTooltip,
                    onSelected: (value) {
                      if (value == 'mute') {
                        unawaited(_basculerSourdine(room));
                      } else if (value == 'info') {
                        _ouvrirFiche(room);
                      }
                    },
                    entrees: [
                      EntreeMenu(
                        valeur: 'mute',
                        libelle: _estEnSourdine(room)
                            ? 'Réactiver les notifications'
                            : 'Mettre en sourdine',
                      ),
                      EntreeMenu(
                        valeur: 'info',
                        libelle: room.otherUserMxid != null
                            ? 'Infos du contact'
                            : 'Infos du groupe',
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: RempartTokens.espaceS),
          // Bandeau : chiffrement, ou compte des résultats en recherche.
          _Pastille(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: RempartTokens.espaceS,
              ),
              child: _isSearching
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        _texteRecherche(events.length),
                        style: theme.textTheme.bodySmall,
                      ),
                    )
                  : EncryptionBanner(room: room, avecFond: false),
            ),
          ),
        ],
      ),
    );
  }

  /// Hauteur des pastilles de l'en-tête flottant.
  static const _hauteurPilule = 52.0;

  /// Hauteur du bandeau posé sous elles (chiffrement ou recherche).
  static const _hauteurBandeau = 32.0;

  static bool _memeJour(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Bandeau d'attente pendant l'envoi d'une pièce jointe : l'upload puis le
  /// chiffrement d'un média prennent plusieurs secondes, sans quoi l'interface
  /// semblerait ne rien faire.
  Widget _buildBandeauEnvoi() {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator.adaptive(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(
            'Envoi de la pièce jointe...',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Bandeau de résultats affiché pendant une recherche dans la conversation.
  String _texteRecherche(int nbResultats) {
    final recherche = _searchQuery.trim();
    final pluriel = nbResultats > 1 ? 's' : '';
    return recherche.isEmpty
        ? 'Tapez pour rechercher dans cette conversation'
        : '$nbResultats message$pluriel trouvé$pluriel · '
            'touchez pour afficher dans le fil';
  }

  /// Recherche sans résultat (à ne pas confondre avec une conversation vide).
  Widget _buildAucunResultat(BuildContext context) {
    final theme = Theme.of(context);
    final recherche = _searchQuery.trim();
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off, size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            recherche.isEmpty
                ? 'Rechercher un message'
                : 'Aucun message trouvé',
            style: theme.textTheme.titleMedium,
          ),
          if (recherche.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Aucun message ne contient « $recherche »',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// La room est-elle en sourdine côté serveur ?
  ///
  /// L'état vit dans les règles de push du compte, pas dans l'app : il suit
  /// donc l'utilisateur d'un appareil à l'autre.
  bool _estEnSourdine(matrix.Room room) =>
      room.pushRuleState != matrix.PushRuleState.notify;

  Future<void> _basculerSourdine(matrix.Room room) async {
    final enSourdine = _estEnSourdine(room);
    try {
      await room.setPushRuleState(
        enSourdine
            ? matrix.PushRuleState.notify
            : matrix.PushRuleState.dontNotify,
      );
      if (!mounted) return;
      // La Room vit hors du graphe Riverpod : sans ce coup de pouce, le libellé
      // du menu resterait sur l'ancien état.
      ref.read(matrixStateNotifierProvider.notifier).state++;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enSourdine
                ? 'Notifications réactivées'
                : 'Conversation mise en sourdine',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible de changer la sourdine : $e')),
      );
    }
  }

  /// Fiche du contact pour un tête-à-tête, du groupe sinon.
  void _ouvrirFiche(matrix.Room room) {
    final contactMxid = room.otherUserMxid;
    unawaited(
      context.push(
        contactMxid != null
            ? '/user/${Uri.encodeComponent(contactMxid)}'
            : '/group/${Uri.encodeComponent(room.id)}',
      ),
    );
  }

  Widget _buildAppBarTitle(matrix.Room room, {required bool isIOS}) {
    // Le mxid du contact est relu à chaque build : la Room est mutable hors du
    // graphe Riverpod, le mémoriser figerait un état antérieur au chargement de
    // ses membres. Seule la résolution Supabase passe par un provider.
    final contactMxid = room.otherUserMxid;
    final contact = contactMxid == null
        ? null
        : ref.watch(contactProfileProvider(contactMxid)).value;
    final title = contact?.name ?? room.displayName;
    final contactSupprime = contact?.deleted ?? false;
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;

    // Toucher l'en-tête ouvre la fiche : celle du contact pour un
    // tête-à-tête, celle du groupe sinon (`otherUserMxid` est null pour un
    // groupe).
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _ouvrirFiche(room),
      child: Row(
        mainAxisSize: isIOS ? MainAxisSize.min : MainAxisSize.max,
        children: [
          UserAvatar(
            name: title,
            // Priorité au profil Supabase, repli sur l'avatar Matrix.
            imageUrl: contact?.avatarUrl,
            mxc: room.avatarUri,
            client: room.client,
            size: 36,
            deleted: contactSupprime,
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Compte supprimé : le nom retomberait sur le localpart
                    // `u_<uuid>`. La pastille le remplace (même parti pris que
                    // dans la liste des conversations).
                    if (contactSupprime)
                      const DeletedAccountBadge()
                    else
                      Flexible(
                        child: Text(
                          title,
                          style: isIOS
                              ? TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? CupertinoColors.white
                                      : CupertinoColors.black,
                                )
                              : Theme.of(context).textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const SizedBox(width: 6),
                    EncryptionBadge(room: room),
                  ],
                ),
                _buildSousTitre(
                  room,
                  contactSupprime: contactSupprime,
                  isIOS: isIOS,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Sous-titre de l'en-tête : la saisie en cours prime sur la présence.
  ///
  /// C'est l'information la plus fraîche et la plus utile ; elle s'efface
  /// d'elle-même et rend la main à « En ligne ».
  Widget _buildSousTitre(
    matrix.Room room, {
    required bool contactSupprime,
    required bool isIOS,
  }) {
    final ecrivent =
        ref.watch(typingUsersProvider(room.id)).value ?? const <String>[];

    if (ecrivent.isNotEmpty) {
      return Text(
        _libelleSaisie(room, ecrivent),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontStyle: FontStyle.italic,
              color: isIOS
                  ? CupertinoColors.systemBlue
                  : Theme.of(context).colorScheme.primary,
            ),
      );
    }

    // Compte supprimé : inutile d'interroger la présence, l'autre ne
    // reviendra pas (la pastille est déjà affichée au-dessus).
    if (contactSupprime || room.otherUserMxid == null) {
      return const SizedBox.shrink();
    }

    // Un flux, et non un instantané : la présence arrive par le sync, donc
    // après l'ouverture de l'écran. Interrogée une seule fois, elle laissait
    // un contact connecté entre-temps invisible jusqu'à ce qu'on ressorte de
    // la conversation.
    final enLigne =
        ref.watch(presenceEnLigneProvider(room.otherUserMxid!)).value ?? false;
    if (!enLigne) return const SizedBox.shrink();

    return Text(
      'En ligne',
      // Le vert de texte mesuré sur les deux plateformes : `Colors.green`
      // tenait 2,61:1, et même le vert système d'iOS, 2,22:1. Pour une icône
      // la convention d'Apple primerait ; pour un texte, la lisibilité.
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: RempartTokens.texteSucces(Theme.of(context).brightness),
          ),
    );
  }

  /// Commandes du bot d'en face, ou une liste vide.
  ///
  /// Silencieux par construction : hors tête-à-tête avec un bot connu, la
  /// frappe d'un « / » ne doit rien faire surgir.
  List<BotCommand> _commandesDuBot(matrix.Room room) {
    final mxid = room.otherUserMxid;
    if (mxid == null) return const <BotCommand>[];
    return ref.watch(commandesDesBotsProvider).value?[mxid] ??
        const <BotCommand>[];
  }

  /// Dans un tête-à-tête, nommer l'autre serait redondant avec l'en-tête ;
  /// dans un groupe, c'est au contraire l'information utile.
  String _libelleSaisie(matrix.Room room, List<String> noms) {
    if (room.otherUserMxid != null) return "en train d'écrire...";
    if (noms.length == 1) return '${noms.first} écrit...';
    if (noms.length == 2) return '${noms[0]} et ${noms[1]} écrivent...';
    return 'plusieurs personnes écrivent...';
  }

  /// Relaie l'état de saisie à Matrix (événement éphémère `m.typing`).
  void _signalerSaisie({required bool actif}) {
    unawaited(
      ref
          .read(matrixServiceProvider)
          .setTyping(widget.conversationId, isTyping: actif)
          .catchError((Object e) {
        // Sans gravité : un indicateur perdu ne justifie pas de remonter une
        // erreur à l'utilisateur.
        debugPrint('Chat: état de saisie non transmis ($e)');
      }),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final isIOS = estIOS;
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isIOS ? CupertinoIcons.chat_bubble : Icons.chat_bubble_outline,
            size: 64,
            color: isIOS
                ? CupertinoColors.systemGrey
                : Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'Aucun message',
            style: isIOS
                ? TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color:
                        isDark ? CupertinoColors.white : CupertinoColors.black,
                  )
                : Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Envoyez le premier message !',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isIOS
                      ? CupertinoColors.systemGrey
                      : Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }
}

/// Aperçu d'une pièce jointe avant envoi, avec sa légende.
///
/// Sans cet écran intermédiaire, joindre une image obligeait à envoyer un
/// second message pour dire ce qu'on en attend, que le destinataire devait
/// rattacher de tête.
/// Ce que l'utilisateur a décidé dans la feuille d'envoi.
@immutable
class _ChoixEnvoi {
  const _ChoixEnvoi({required this.legende, required this.hauteQualite});

  final String legende;

  /// Vrai : les photos partent telles quelles. Faux : elles sont allégées.
  final bool hauteQualite;
}

/// Aperçu des médias choisis, légende commune, et choix de la qualité.
class _FeuilleLegende extends StatefulWidget {
  const _FeuilleLegende({required this.fichiers, this.limiteEnvoi});

  final List<matrix.MatrixFile> fichiers;

  /// Taille maximale acceptée par le serveur, si elle est connue. Une vidéo
  /// au-dessus est refusée à l'envoi, et rien ne le disait avant d'essayer.
  final int? limiteEnvoi;

  @override
  State<_FeuilleLegende> createState() => _FeuilleLegendeState();
}

class _FeuilleLegendeState extends State<_FeuilleLegende> {
  final _controller = TextEditingController();
  bool _hd = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<matrix.MatrixFile> get _fichiers => widget.fichiers;

  bool _estImage(matrix.MatrixFile f) => f.mimeType.startsWith('image/');

  /// L'interrupteur ne s'affiche que s'il change quelque chose : une vidéo ou
  /// un document partent tels quels de toute façon.
  bool get _qualiteEnJeu => _fichiers.any(
        (f) => _estImage(f) && f.size > 300 * 1024,
      );

  int get _poidsTotal => _fichiers.fold(0, (total, f) => total + f.size);

  /// Fichiers que le serveur refusera, quoi qu'on fasse.
  ///
  /// La compression ne les sauverait pas : elle ne touche pas aux vidéos, qui
  /// sont précisément ce qui dépasse.
  List<matrix.MatrixFile> get _tropLourds {
    final limite = widget.limiteEnvoi;
    if (limite == null) return const [];
    return _fichiers.where((f) => f.size > limite).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nombre = _fichiers.length;

    return Padding(
      // Remonter au-dessus du clavier : la feuille est en bas de l'écran.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Un seul média : on le montre en grand, c'est ce qu'on regarde.
              // Plusieurs : une bande de vignettes, qui dit le nombre et
              // l'ordre sans écraser le reste de la feuille.
              if (nombre == 1)
                _apercuUnique(_fichiers.first)
              else
                SizedBox(
                  height: 96,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: nombre,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) => _vignette(_fichiers[i]),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                nombre == 1
                    ? CompressionImage.poidsLisible(_poidsTotal)
                    : '$nombre éléments · '
                        '${CompressionImage.poidsLisible(_poidsTotal)}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              if (_tropLourds.isNotEmpty) ...[
                const SizedBox(height: 8),
                // Dit avant d'engager l'envoi : le serveur refuserait, et
                // l'utilisateur n'aurait qu'une pastille rouge sans cause.
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _tropLourds.length == _fichiers.length
                              ? 'Trop volumineux pour le serveur '
                                  '(maximum '
                                  '${CompressionImage.poidsLisible(widget.limiteEnvoi!)}). '
                                  "L'envoi échouera."
                              : '${_tropLourds.length} élément(s) dépassent '
                                  '${CompressionImage.poidsLisible(widget.limiteEnvoi!)} '
                                  'et seront refusés.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_qualiteEnJeu) ...[
                const SizedBox(height: 4),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _hd,
                  onChanged: (v) => setState(() => _hd = v),
                  title: const Text("Qualité d'origine (HD)"),
                  subtitle: Text(
                    _hd
                        ? 'Les photos partent telles quelles, sans perte.'
                        : 'Les photos sont allégées : plus rapide, et '
                            "indiscernable à l'écran.",
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                autofocus: true,
                maxLines: 3,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: nombre > 1
                      ? "Une légende pour l'ensemble (facultatif)"
                      : 'Ajouter une légende (facultatif)',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Annuler'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(
                      context,
                      _ChoixEnvoi(
                        legende: _controller.text,
                        hauteQualite: _hd,
                      ),
                    ),
                    icon: const Icon(Icons.send),
                    label: Text(
                      nombre > 1 ? 'Envoyer ($nombre)' : 'Envoyer',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _apercuUnique(matrix.MatrixFile fichier) {
    if (!_estImage(fichier)) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.insert_drive_file, size: 32),
        title: Text(
          fichier.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 260),
        child: Image.memory(
          fichier.bytes,
          fit: BoxFit.contain,
          width: double.infinity,
          // La hauteur affichée ne dépasse jamais 260 : décoder à cette
          // hauteur suffit quel que soit le format, le rapport étant gardé.
          cacheHeight: (260 * MediaQuery.devicePixelRatioOf(context)).round(),
        ),
      ),
    );
  }

  Widget _vignette(matrix.MatrixFile fichier) {
    final theme = Theme.of(context);
    if (!_estImage(fichier)) {
      return Container(
        width: 96,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Icon(
          fichier.mimeType.startsWith('video/')
              ? Icons.videocam_outlined
              : Icons.insert_drive_file,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.memory(
        fichier.bytes,
        width: 96,
        height: 96,
        fit: BoxFit.cover,
        // Quinze photos choisies d'un coup, c'étaient quinze décodages en
        // pleine résolution pour des vignettes de 96 points. Le double de
        // leur côté, pour qu'un recadrage au carré reste net jusqu'à un
        // format 2:1.
        cacheWidth: (2 * 96 * MediaQuery.devicePixelRatioOf(context)).round(),
      ),
    );
  }
}

/// Séparateur de jour, en pastille posée au milieu du fil.
///
/// Sans lui, deux messages à trois semaines d'écart se suivent sans rien qui
/// marque la coupure : seule l'heure change, et elle ne dit pas quel jour.
class _SeparateurDate extends StatelessWidget {
  const _SeparateurDate({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RempartTokens.espaceM),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: RempartTokens.espaceM,
            vertical: 5,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: theme.colorScheme.outlineVariant),
            boxShadow: RempartTokens.ombreLegere(theme.brightness),
          ),
          child: Text(
            _libelle(date),
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  String _libelle(DateTime date) {
    final maintenant = DateTime.now();
    final jour = DateTime(date.year, date.month, date.day);
    final aujourdhui =
        DateTime(maintenant.year, maintenant.month, maintenant.day);
    final ecart = aujourdhui.difference(jour).inDays;
    if (ecart == 0) return "Aujourd'hui";
    if (ecart == 1) return 'Hier';
    if (ecart < 7) {
      return toBeginningOfSentenceCase(DateFormat.EEEE('fr').format(date)) ??
          '';
    }
    if (date.year == maintenant.year) {
      return DateFormat.MMMMd('fr').format(date);
    }
    return DateFormat.yMMMMd('fr').format(date);
  }
}

/// Pastille flottante de l'en-tête : fond translucide, flou et léger relief.
class _Pastille extends StatelessWidget {
  const _Pastille({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            // Assez opaque pour que le texte reste lisible sur une bulle
            // sombre, assez transparent pour qu'on voie ce qui passe dessous.
            color: theme.colorScheme.surface.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.62 : 0.72,
            ),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
            ),
            boxShadow: RempartTokens.ombreLegere(theme.brightness),
          ),
          child: child,
        ),
      ),
    );
  }
}
