import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../../../app/theme.dart';
import '../../../core/mouvement.dart';
import '../../../core/plateforme.dart';
import '../../../core/utils/secret_message.dart';
import '../../../data/models/matrix_extensions.dart';
import '../../../data/providers/taille_texte.dart';
import '../../../data/providers/vitesse_vocal.dart';
import '../../../data/services/matrix_service.dart';
import '../common/user_avatar.dart';
import 'message_riche.dart';

/// Bulle de message dans le chat (utilise les Events Matrix)
class MessageBubble extends ConsumerWidget {
  const MessageBubble({
    required this.event,
    required this.isMine,
    super.key,
    this.timeline,
    this.showAvatar = false,
    this.onTap,
    this.onLongPress,
    this.onReplyTap,
    this.onReagir,
    this.onBouton,
    this.album,
    this.highlighted = false,
  });

  final matrix.Event event;

  /// Timeline de la room, porteuse des agrégations (éditions, réactions).
  ///
  /// Sans elle la bulle affiche le message d'origine : les modifications
  /// ultérieures ne peuvent pas être résolues.
  final matrix.Timeline? timeline;

  /// Appui sur une réaction déjà posée : l'ajoute ou la retire.
  final void Function(String symbole)? onReagir;

  /// Appui sur un bouton proposé par un bot : renvoie sa valeur.
  /// Reçoit le **libellé** du bouton et sa **valeur** : le premier s'affiche
  /// dans la conversation, la seconde part à l'agent.
  final void Function(String texte, String valeur)? onBouton;

  /// Médias d'un même envoi, [event] compris, ou null s'il est seul.
  ///
  /// Quinze photos partagées ensemble remplissaient quinze bulles et toute la
  /// hauteur du fil ; elles tiennent ici dans une grille.
  final List<matrix.Event>? album;

  final bool isMine;
  final bool showAvatar;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onReplyTap;

  /// Message mis en évidence après un saut depuis la recherche : un fond
  /// temporaire aide à le repérer une fois replacé dans son contexte.
  final bool highlighted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Style unique du corps d'un message, quel que soit le chemin de rendu.
    // Le texte brut prenait `bodyLarge` (15,5) tandis que le rendu riche
    // n'imposait rien et héritait de `bodyMedium` (14) : d'un message à
    // l'autre, la taille changeait selon qu'il portait ou non une mise en
    // forme, donc selon qu'il venait d'un agent ou d'une personne.
    final styleCorps = theme.textTheme.bodyLarge!.copyWith(
      fontSize: (theme.textTheme.bodyLarge!.fontSize ?? 15.5) *
          ref.watch(tailleTexteProvider).facteur,
    );
    final colorScheme = theme.colorScheme;

    // Contenu à rendre : le message d'origine avec ses éditions appliquées.
    // `event` reste la référence d'identité (eventId, horodatage, statut), car
    // c'est lui que visent la réponse, la suppression et le saut depuis la
    // recherche : une édition a son propre eventId, viser celui-ci casserait
    // ces actions.
    final timeline = this.timeline;
    final affiche = timeline == null ? event : event.getDisplayEvent(timeline);
    final modifie = timeline != null && event.aEteModifie(timeline);
    final lu = isMine && event.luParUnAutre;
    final legende = affiche.legendePieceJointe;

    return AnimatedContainer(
      duration: dureeAnimation(context, const Duration(milliseconds: 300)),
      color: highlighted
          ? colorScheme.primary.withValues(alpha: 0.18)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(
        horizontal: RempartTokens.espaceS,
        vertical: 3,
      ),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Avatar (pour les messages des autres)
          if (!isMine && showAvatar)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildSenderAvatar(context),
            )
          else if (!isMine)
            const SizedBox(width: 40),

          // Bulle de message, et sous elle ses réactions
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
          GestureDetector(
              onTap: onTap,
              onLongPress: onLongPress,
              child: Container(
                constraints: BoxConstraints(maxWidth: _largeurBulle(context)),
                // Bulle « posée » : dégradé très léger sur les miennes, liseré
                // et ombre courte sur celles des autres. Une couleur plate sur
                // un fond plat donne l'impression d'un tableur.
                decoration: BoxDecoration(
                  color: isMine ? null : colorScheme.surface,
                  gradient: isMine
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            colorScheme.primary,
                            Color.alphaBlend(
                              Colors.black.withValues(alpha: 0.10),
                              colorScheme.primary,
                            ),
                          ],
                        )
                      : null,
                  border: isMine
                      ? null
                      : Border.all(color: colorScheme.outlineVariant),
                  boxShadow: RempartTokens.ombreLegere(theme.brightness),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(RempartTokens.rayonBulle),
                    topRight: const Radius.circular(RempartTokens.rayonBulle),
                    bottomLeft: Radius.circular(
                      isMine ? RempartTokens.rayonBulle : 6,
                    ),
                    bottomRight: Radius.circular(
                      isMine ? 6 : RempartTokens.rayonBulle,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Réponse à un message
                    if (event.isReply) _buildReplyPreview(context),

                    // Contenu du message
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Dans un groupe, qui parle doit se lire sans
                          // remonter à l'avatar : plusieurs voix se suivent.
                          if (!isMine && showAvatar && !event.room.isDirectChat)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                event.senderDisplayName,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: _couleurExpediteur(event.senderId),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          // Pièces jointes (images, fichiers)
                          if (affiche.isImageMessage ||
                              affiche.isFileMessage ||
                              affiche.isVideoMessage ||
                              affiche.isAudioMessage)
                            _buildAttachment(context, affiche),

                          // Légende d'une pièce jointe : c'est un texte à
                          // part entière, sous le fichier.
                          if (legende != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                legende,
                                style: styleCorps.copyWith(
                                  color: isMine
                                      ? colorScheme.onPrimary
                                      : colorScheme.onSurface,
                                ),
                              ),
                            ),

                          // Texte du message. Un corps mis en forme
                          // (`formatted_body`) passe par le rendu riche : sans
                          // lui, un bloc de code d'agent arriverait aplati.
                          if (legende == null &&
                              !affiche.isAudioMessage &&
                              (affiche.isTextMessage ||
                                  (affiche.plaintextBody.isNotEmpty &&
                                      !affiche.isImageMessage)))
                            // Un code ou un mot de passe reste flouté jusqu'à
                            // ce qu'on le demande : de quoi lire ses messages
                            // en public sans livrer un secret au premier
                            // regard par-dessus l'épaule. Le masque enveloppe
                            // tout le corps, et non le seul jeton : « le mdp
                            // du wifi est ... » en dit déjà trop.
                            _PeutEtreMasque(
                              masquer: !affiche.isDeleted &&
                                  ressembleAUnSecret(affiche.plaintextBody),
                              surFondPropre: isMine,
                              // Le rendu riche ne pose aucune taille et lit
                              // celle qu'il hérite : c'est par ce style que
                              // les deux chemins se rejoignent, et par lui que
                              // le réglage de l'utilisateur les atteint tous
                              // les deux.
                              enfant: DefaultTextStyle.merge(
                                style: styleCorps,
                                child: affiche.corpsFormate != null &&
                                        !affiche.isDeleted
                                    ? MessageRiche(
                                        formattedBody: affiche.corpsFormate!,
                                        couleurTexte: isMine
                                            ? colorScheme.onPrimary
                                            : colorScheme.onSurface,
                                        surFondPropre: isMine,
                                      )
                                    // `TexteAvecLiens` et non `Text` : un
                                    // message sans mise en forme contient lui
                                    // aussi des adresses, mortes jusqu'ici.
                                    : TexteAvecLiens(
                                        texte: affiche.displayText,
                                        surFondPropre: isMine,
                                        style: styleCorps.copyWith(
                                          color: isMine
                                              ? colorScheme.onPrimary
                                              : colorScheme.onSurface,
                                          fontStyle: affiche.isDeleted
                                              ? FontStyle.italic
                                              : FontStyle.normal,
                                        ),
                                      ),
                              ),
                            ),

                          const SizedBox(height: 4),

                          // Heure et statut
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                DateFormat.Hm().format(event.originServerTs),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontSize: 11,
                                  color: isMine
                                      ? colorScheme.onPrimary.withAlpha(190)
                                      : colorScheme.onSurfaceVariant,
                                ),
                              ),
                              if (modifie) ...[
                                const SizedBox(width: 4),
                                Text(
                                  'modifié',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                    color: isMine
                                        ? colorScheme.onPrimary.withAlpha(179)
                                        : colorScheme.onSurface.withAlpha(128),
                                  ),
                                ),
                              ],
                              if (isMine) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  _iconeStatut(lu: lu),
                                  size: 14,
                                  color: _couleurStatut(colorScheme, lu: lu),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
                _Boutons(event: event, onBouton: onBouton),
                _Reactions(
                  event: event,
                  timeline: timeline,
                  onReagir: onReagir,
                ),
              ],
            ),
          ),

          // Espace pour les messages envoyés
          if (isMine) const SizedBox(width: 40),
        ],
      ),
    );
  }

  /// Couleur du nom d'un participant, stable pour un même mxid.
  ///
  /// Reprend l'encre des avatars : le nom et la pastille de la même personne
  /// se répondent, ce qui aide à suivre une discussion à plusieurs.
  static Color _couleurExpediteur(String mxid) =>
      RempartTokens.avatars[mxid.hashCode.abs() % RempartTokens.avatars.length].$2;

  Widget _buildSenderAvatar(BuildContext context) {
    return UserAvatar(
      name: event.senderDisplayName,
      mxc: event.senderAvatarUri,
      client: event.room.client,
      size: 32,
    );
  }

  Widget _buildReplyPreview(BuildContext context) {
    final theme = Theme.of(context);
    final couleurs = CouleursCitation.pour(
      estLaMienne: isMine,
      schema: theme.colorScheme,
      luminosite: theme.brightness,
    );

    return FutureBuilder<matrix.Event?>(
      future: event.fetchReplyEvent(),
      builder: (context, snapshot) {
        final replyEvent = snapshot.data;

        return GestureDetector(
          onTap: onReplyTap,
          child: Container(
            margin: const EdgeInsets.only(left: 8, right: 8, top: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: couleurs.fond,
              borderRadius: BorderRadius.circular(8),
              border: Border(
                left: BorderSide(
                  color: couleurs.barre,
                  // Plus épaisse : c'est elle qui signale la citation d'un
                  // coup d'oeil, avant même la nuance de fond.
                  width: 4,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // `nomLisibleDeLExpediteur` et non `senderDisplayName` :
                  // celui-ci retombe sur le localpart, donc affichait
                  // « u_fd8de5c7… » au-dessus de la citation tant que les
                  // membres n'étaient pas chargés.
                  replyEvent?.nomLisibleDeLExpediteur ?? 'Contact inconnu',
                  // Rien ne borne un display name Matrix, et celui-ci vient
                  // d'un tiers : sans troncature, un nom de 200 caractères
                  // étirait la citation sur toute la hauteur de l'écran.
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: couleurs.nom,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  replyEvent?.texteApercu ?? '...',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: couleurs.texte),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAttachment(BuildContext context, matrix.Event affiche) {
    final fileInfo = affiche.fileInfo;

    final groupe = album;
    if (groupe != null && groupe.length > 1) {
      return _GrilleAlbum(evenements: groupe);
    }

    if (affiche.isImageMessage) {
      return _ImageJointe(event: affiche);
    }

    if (affiche.isAudioMessage) {
      return _VocalJoint(event: affiche, isMine: isMine);
    }

    // Fichier générique
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(26),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getFileIcon(fileInfo?.mimeType ?? ''),
            color:
                isMine ? Colors.white : Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileInfo?.fileName ?? 'Fichier',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: isMine ? Colors.white : null,
                  ),
                ),
                if (fileInfo?.formattedSize.isNotEmpty ?? false)
                  Text(
                    fileInfo!.formattedSize,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isMine
                          ? Colors.white70
                          : Theme.of(context).colorScheme.outline,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Statut d'un message envoyé.
  ///
  /// La double coche est réservée à la lecture effective par le destinataire.
  /// Elle était auparavant liée à `EventStatus.synced`, qui ne dit rien de
  /// plus que « le serveur a accepté le message » : tout message apparaissait
  /// donc comme lu à la seconde où il partait.
  IconData _iconeStatut({required bool lu}) {
    switch (event.status) {
      case matrix.EventStatus.error:
        return Icons.error_outline;
      case matrix.EventStatus.sending:
        return Icons.access_time;
      case matrix.EventStatus.sent:
      case matrix.EventStatus.synced:
        return lu ? Icons.done_all : Icons.done;
    }
  }

  Color _couleurStatut(ColorScheme colorScheme, {required bool lu}) {
    if (event.status == matrix.EventStatus.error) return Colors.red;
    return lu ? Colors.lightBlueAccent : colorScheme.onPrimary.withAlpha(179);
  }

  IconData _getFileIcon(String mimeType) {
    if (mimeType.startsWith('image/')) return Icons.image;
    if (mimeType.startsWith('video/')) return Icons.videocam;
    if (mimeType.startsWith('audio/')) return Icons.audiotrack;
    if (mimeType.contains('pdf')) return Icons.picture_as_pdf;
    if (mimeType.contains('word') || mimeType.contains('document')) {
      return Icons.description;
    }
    return Icons.insert_drive_file;
  }
}

/// Image d'un message, téléchargée ET déchiffrée.
///
/// Dans une room chiffrée, le média est chiffré côté serveur : son URL HTTP
/// brute ne renvoie que du chiffré, illisible par `Image.network` (vignette
/// bloquée sur son indicateur de chargement). On passe donc par
/// `downloadAndDecryptAttachment`, qui vaut aussi pour les rooms en clair.
///
/// Widget à état pour ne télécharger qu'une fois : la bulle est reconstruite à
/// chaque mise à jour de la timeline, un FutureBuilder relancerait la
/// récupération à chaque build.
class _ImageJointe extends StatefulWidget {
  const _ImageJointe({required this.event, this.enGrille = false});

  final matrix.Event event;

  /// Dans une mosaïque, l'image remplit sa case carrée au lieu de garder ses
  /// proportions : des photos de formats mêlés donneraient sinon une grille
  /// dentelée.
  final bool enGrille;

  @override
  State<_ImageJointe> createState() => _ImageJointeState();
}

class _ImageJointeState extends State<_ImageJointe> {
  Uint8List? _octets;
  bool _echec = false;

  @override
  void initState() {
    super.initState();
    unawaited(_charger());
  }

  Future<void> _charger() async {
    try {
      final fichier = await widget.event.downloadAndDecryptAttachment();
      if (mounted) {
        setState(() => _octets = fichier.bytes);
      }
    } catch (e) {
      debugPrint('MessageBubble: image non récupérée ($e)');
      if (mounted) {
        setState(() => _echec = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_echec) {
      return Container(
        height: 150,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.broken_image, size: 48),
      );
    }

    final octets = _octets;
    if (octets == null) {
      return Container(
        height: 150,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.enGrille ? 4 : 8),
      child: Image.memory(
        octets,
        fit: BoxFit.cover,
        width: double.infinity,
        // Décodée à la taille où elle s'affiche, et non à celle du capteur :
        // une photo de 12 Mpx occupait environ 48 Mo en mémoire pour une
        // vignette de 280 points, et un fil chargé de photos faisait saccader
        // puis tomber un Android modeste. La largeur maximale d'une bulle
        // couvre aussi les cases d'un album, qui en font la moitié et se
        // recadrent au carré : le double de leur largeur tient jusqu'à un
        // format 2:1. La visionneuse, elle, garde la pleine résolution.
        cacheWidth:
            (_largeurBulle(context) * MediaQuery.devicePixelRatioOf(context))
                .round(),
        errorBuilder: (context, error, stack) => Container(
          height: 150,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.broken_image, size: 48),
        ),
      ),
    );
  }
}

/// Enveloppe un contenu d'un voile qui se lève au toucher.
///
/// Sans [masquer], le widget s'efface complètement : pas de `Stack` ni de
/// filtre inutile sur les bulles ordinaires, qui sont l'immense majorité.
class _PeutEtreMasque extends StatefulWidget {
  const _PeutEtreMasque({
    required this.masquer,
    required this.surFondPropre,
    required this.enfant,
  });

  final bool masquer;
  final bool surFondPropre;
  final Widget enfant;

  @override
  State<_PeutEtreMasque> createState() => _PeutEtreMasqueState();
}

class _PeutEtreMasqueState extends State<_PeutEtreMasque> {
  bool _revele = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.masquer || _revele) return widget.enfant;

    final theme = Theme.of(context);
    final couleur = widget.surFondPropre
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurfaceVariant;

    return GestureDetector(
      onTap: () => setState(() => _revele = true),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Le contenu reste en place sous le voile : la bulle garde sa taille,
          // donc la liste ne saute pas au moment où on le révèle.
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
            child: Opacity(opacity: 0.55, child: widget.enfant),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.visibility_outlined, size: 15, color: couleur),
              const SizedBox(width: RempartTokens.espaceXs),
              Text(
                'Appuyer pour afficher',
                style: theme.textTheme.labelMedium?.copyWith(color: couleur),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


/// Les réactions posées sous un message.
///
/// Un appui bascule la sienne : c'est le geste attendu partout ailleurs, et
/// c'est aussi ce qu'un agent qui propose « ✅ pour approuver » vient lire.
class _Reactions extends StatelessWidget {
  const _Reactions({
    required this.event,
    required this.timeline,
    required this.onReagir,
  });

  final matrix.Event event;
  final matrix.Timeline? timeline;
  final void Function(String symbole)? onReagir;

  @override
  Widget build(BuildContext context) {
    final fil = timeline;
    // Sans timeline, les agrégations ne sont pas résolues : mieux vaut ne rien
    // montrer qu'un décompte faux.
    if (fil == null) return const SizedBox.shrink();

    final moi = event.room.client.userID;
    final reactions = MatrixService.reactionsDe(event, fil, moi);
    if (reactions.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final reaction in reactions)
            InkWell(
              onTap: onReagir == null
                  ? null
                  : () => onReagir!(reaction.symbole),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: reaction.parMoi
                      ? theme.colorScheme.primary.withValues(alpha: 0.16)
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                  border: reaction.parMoi
                      ? Border.all(color: theme.colorScheme.primary)
                      : null,
                ),
                child: Text(
                  reaction.nombre > 1
                      ? '${reaction.symbole} ${reaction.nombre}'
                      : reaction.symbole,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
        ],
      ),
    );
  }
}


/// Boutons proposés par un bot sous son message.
///
/// Matrix n'a pas de standard pour cela : le champ `fr.rempart.boutons` est à
/// nous, et les autres clients l'ignorent. C'est pourquoi le texte du message
/// doit rester compréhensible sans eux, ce que la passerelle rappelle aux
/// agents : sur Element, la question doit rester répondable à la main.
class _Boutons extends StatelessWidget {
  const _Boutons({required this.event, required this.onBouton});

  final matrix.Event event;
  final void Function(String texte, String valeur)? onBouton;

  static const _champ = 'fr.rempart.boutons';

  @override
  Widget build(BuildContext context) {
    // Un message effacé ne propose plus rien : ses boutons partiraient
    // répondre à une question qui n'existe plus.
    if (event.redacted || onBouton == null) return const SizedBox.shrink();

    final brut = event.content[_champ];
    if (brut is! List || brut.isEmpty) return const SizedBox.shrink();

    final boutons = <({String texte, String valeur})>[];
    for (final item in brut) {
      if (item is! Map) continue;
      final texte = (item['texte'] as String?)?.trim() ?? '';
      final valeur = (item['valeur'] as String?)?.trim() ?? '';
      if (texte.isNotEmpty && valeur.isNotEmpty) {
        boutons.add((texte: texte, valeur: valeur));
      }
    }
    if (boutons.isEmpty) return const SizedBox.shrink();

    // Deux par ligne, et le dernier seul prend toute la largeur : c'est la
    // forme d'un choix binaire coiffé d'un retrait (« Approuver / Toujours »,
    // puis « Annuler »), et elle se lit sans hésiter le pouce en l'air.
    final lignes = <List<({String texte, String valeur})>>[];
    for (var i = 0; i < boutons.length; i += 2) {
      lignes.add(boutons.sublist(i, math.min(i + 2, boutons.length)));
    }

    // Meme largeur maximale que la bulle : poses sous elle et non dedans, les
    // boutons s'etalaient sinon sur toute la fenetre, debordant visiblement du
    // message auquel ils repondent.
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: _largeurBulle(context)),
        child: Column(
        children: [
          for (final ligne in lignes)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  for (final bouton in ligne) ...[
                    Expanded(
                      child: _BoutonReponse(
                        texte: bouton.texte,
                        onTap: () => onBouton!(bouton.texte, bouton.valeur),
                      ),
                    ),
                    if (bouton != ligne.last) const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Un bouton proposé sous un message d'agent.
///
/// Assez haut pour être touché sans viser (48 points, la cible minimale
/// recommandée), et teinté plutôt que cerné : sur le fond d'une bulle, une
/// simple bordure se perd, surtout en thème sombre.
/// Part de la largeur d'écran qu'occupe au plus une bulle, boutons compris.
const _partLargeurBulle = 0.78;

/// Largeur au-delà de laquelle une bulle cesse de s'élargir.
///
/// Une ligne de texte trop longue se lit mal : l'oeil perd le début de la
/// suivante. Sur un téléphone, c'est la part ci-dessus qui mord la première ;
/// sur un écran de bureau, où 78 % de la fenêtre font un pavé de deux mille
/// points de large, c'est ce plafond qui agit.
const _largeurMaxBulle = 560.0;

double _largeurBulle(BuildContext context) => math.min(
      MediaQuery.of(context).size.width * _partLargeurBulle,
      _largeurMaxBulle,
    );

class _BoutonReponse extends StatelessWidget {
  const _BoutonReponse({required this.texte, required this.onTap});

  final String texte;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final couleur = theme.colorScheme.primary;

    return Material(
      color: couleur.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: couleur.withValues(alpha: 0.35)),
          ),
          child: Text(
            texte,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelLarge?.copyWith(
              color: couleur,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Message vocal : un bouton, une barre de progression, une durée.
///
/// Le média est téléchargé ET déchiffré comme une image, puis lu depuis la
/// mémoire : dans une room chiffrée, l'URL brute ne rend que du chiffré, que le
/// lecteur refuserait sans rien expliquer.
///
/// Le téléchargement n'a lieu qu'au premier appui sur « lire », et non à
/// l'affichage : une conversation pleine de vocaux tirerait sinon plusieurs
/// mega-octets sans que personne ne les ait demandés.
class _VocalJoint extends ConsumerStatefulWidget {
  const _VocalJoint({required this.event, required this.isMine});

  final matrix.Event event;
  final bool isMine;

  @override
  ConsumerState<_VocalJoint> createState() => _VocalJointState();
}

class _VocalJointState extends ConsumerState<_VocalJoint> {
  final _lecteur = AudioPlayer();

  Uint8List? _octets;
  bool _chargement = false;

  /// Ce qui a échoué, et à quelle étape. Null tant que tout va bien.
  ///
  /// Deux moitiés qui se ressemblent à l'écran et se soignent autrement : le
  /// vocal n'est pas arrivé, ou il est arrivé et le lecteur n'en veut pas. Un
  /// message unique les confondait, et envoyait chercher la panne du mauvais
  /// côté.
  String? _echec;
  bool _joue = false;

  /// La source est-elle déjà armée dans le lecteur ?
  ///
  /// Sans ce drapeau, chaque appui sur « lire » reposait la source, ce qui
  /// remet la position à zéro : une pause suivie d'une reprise recommençait
  /// le vocal depuis le début, et se placer quelque part n'aurait servi à
  /// rien.
  bool _sourcePrete = false;

  Duration _position = Duration.zero;

  /// Gardés pour être annulés : la bulle est détruite au défilement, et des
  /// écoutes laissées derrière appelleraient `setState` sur un widget mort.
  final _abonnements = <StreamSubscription<dynamic>>[];

  @override
  void initState() {
    super.initState();
    // `release` (le défaut sur Android) libère la source à la fin du vocal :
    // il faudrait la reposer pour réécouter, et toute position choisie serait
    // perdue. `stop` garde le lecteur chargé.
    unawaited(_lecteur.setReleaseMode(ReleaseMode.stop));
    _abonnements.addAll([
      _lecteur.onPlayerStateChanged.listen((etat) {
        if (mounted) setState(() => _joue = etat == PlayerState.playing);
      }),
      _lecteur.onPositionChanged.listen((p) {
        if (mounted) setState(() => _position = p);
      }),
      // Les pannes de lecture n'arrivent pas en exception : le lecteur les
      // pose sur son flux d'evenements, et sans cette ecoute elles se
      // perdaient dans la zone asynchrone. Le bouton restait alors muet, sans
      // un mot, ce qui se lit comme une application cassee.
      _lecteur.eventStream.listen(
        (_) {},
        onError: (Object erreur) {
          debugPrint('MessageBubble: lecture impossible ($erreur)');
          if (mounted) setState(() => _echec = _echecDeLecture);
        },
      ),
      _lecteur.onPlayerComplete.listen((_) {
        // Revenir au début : sans cela, un second appui ne relance rien, le
        // lecteur étant resté à la fin.
        unawaited(_lecteur.seek(Duration.zero));
        if (mounted) setState(() => _position = Duration.zero);
      }),
    ]);
  }

  @override
  void dispose() {
    for (final abonnement in _abonnements) {
      unawaited(abonnement.cancel());
    }
    unawaited(_lecteur.dispose());
    super.dispose();
  }

  /// Silhouette envoyée par l'expéditeur (MSC3246), entre 0 et 1024.
  ///
  /// Vide si le message vient d'un client qui n'en met pas : le dessin retombe
  /// alors sur une ligne régulière, plutôt que sur rien.
  List<int> get _formeOnde {
    final audio = widget.event.content['org.matrix.msc1767.audio'];
    final brut = audio is Map ? audio['waveform'] : null;
    if (brut is! List) return const [];
    return [
      for (final v in brut)
        if (v is num) v.toInt().clamp(0, 1024),
    ];
  }

  /// Durée annoncée par l'expéditeur, en millisecondes (`info.duration`).
  ///
  /// Zéro si elle manque : un client tiers peut envoyer un audio sans elle. La
  /// barre reste alors à plat, mais la lecture fonctionne.
  Duration get _duree {
    final info = widget.event.content['info'];
    final ms = info is Map ? info['duration'] : null;
    return ms is num ? Duration(milliseconds: ms.toInt()) : Duration.zero;
  }

  /// Télécharge le vocal si besoin et arme la source. Rend faux si rien n'est
  /// jouable, auquel cas la bulle affiche déjà son échec.
  Future<bool> _assurerSource() async {
    if (_sourcePrete) return true;
    if (_octets == null) {
      setState(() => _chargement = true);
      try {
        final fichier = await widget.event.downloadAndDecryptAttachment();
        _octets = fichier.bytes;
      } catch (e) {
        debugPrint('MessageBubble: vocal non récupéré ($e)');
        if (mounted) setState(() => _echec = 'Vocal non récupéré');
        return false;
      } finally {
        if (mounted) setState(() => _chargement = false);
      }
    }
    final octets = _octets;
    if (octets == null) return false;
    try {
      // La taille part au journal : un vocal vide ou resté chiffré se
      // reconnaît là, et pas à l'écran, où les deux se ressemblent.
      debugPrint('MessageBubble: vocal prêt, ${octets.length} octets');
      await _lecteur.setSourceBytes(octets, mimeType: 'audio/mp4');
      _sourcePrete = true;
      return true;
    } catch (e) {
      debugPrint('MessageBubble: lecture impossible ($e)');
      if (mounted) setState(() => _echec = _echecDeLecture);
      return false;
    }
  }

  Future<void> _basculer() async {
    if (_joue) {
      await _lecteur.pause();
      return;
    }
    if (!await _assurerSource()) return;
    // La vitesse se repose à chaque lecture : selon les plateformes, le
    // lecteur la ramène à 1 en changeant de source.
    await _lecteur.setPlaybackRate(ref.read(vitesseVocalProvider));
    await _lecteur.resume();
  }

  /// Se place dans le vocal, [fraction] valant 0 au début et 1 à la fin.
  ///
  /// Ne lance pas la lecture : on peut vouloir se placer avant d'écouter. Si
  /// le vocal joue déjà, il continue depuis le nouveau point.
  Future<void> _allerA(double fraction) async {
    final duree = _duree;
    // Sans durée annoncée (client tiers avare), l'abscisse ne veut rien dire :
    // on ne saurait pas où l'on va.
    if (duree == Duration.zero) return;
    final cible = duree * fraction.clamp(0.0, 1.0);
    if (!await _assurerSource()) return;
    await _lecteur.seek(cible);
    if (mounted) setState(() => _position = cible);
  }

  /// Passe au cran de vitesse suivant, pour ce vocal et tous les autres.
  void _vitesseSuivante() {
    final suivante = vitesseSuivante(ref.read(vitesseVocalProvider));
    ref.read(vitesseVocalProvider.notifier).state = suivante;
    // En cours d'écoute, le changement doit s'entendre tout de suite.
    if (_joue) unawaited(_lecteur.setPlaybackRate(suivante));
  }

  String _mmss(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final couleur =
        widget.isMine ? Colors.white : theme.colorScheme.onSurfaceVariant;
    final duree = _duree;
    final avancement = duree.inMilliseconds > 0
        ? (_position.inMilliseconds / duree.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    final echec = _echec;
    if (echec != null) {
      // Sur le web, la cause est presque toujours la meme et elle ne vient pas
      // de Rempart : le vocal est de l'AAC dans un M4A, format qu'un
      // navigateur sans codec proprietaire refuse de decoder. Opera sous
      // Linux, par exemple, rend « » a `canPlayType('audio/mp4')` la ou Chrome
      // rend « probably ». Dire « vocal illisible » ferait accuser le message,
      // qui est intact et s'ecoute ailleurs.
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic_off_outlined, color: couleur, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(echec, style: TextStyle(color: couleur)),
          ),
        ],
      );
    }

    return SizedBox(
      width: 236,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Les trois commandes sur une ligne, centrées les unes sur les
          // autres : lecture, silhouette, vitesse. La durée est descendue
          // sous elles : une valeur qui se lit et ne se touche pas n'a
          // rien à faire dans cette rangée, et tant qu'elle y était, sa
          // hauteur poussait le bouton de lecture sous la silhouette.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: _chargement ? null : _basculer,
                // Sans elle, TalkBack et VoiceOver annonçaient « bouton », sans
                // dire s'il lance ou arrête, sur le geste central du vocal.
                tooltip: _joue ? 'Pause' : 'Écouter le vocal',
                visualDensity: VisualDensity.compact,
                icon: _chargement
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: couleur,
                        ),
                      )
                    : Icon(
                        _joue ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: couleur,
                      ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // La silhouette fait office de barre de progression : on
                    // touche donc dedans pour se placer, à l'endroit même où l'on
                    // lit où l'on en est. Un appui seulement, pas un glissement :
                    // le glissement horizontal appartient déjà à la réponse
                    // rapide, et le lui prendre sur les vocaux ferait disparaître
                    // le geste sans prévenir.
                    Semantics(
                      // La silhouette sert de barre de progression : à
                      // l'oreille, elle ne disait rien. Elle annonce
                      // maintenant où l'on en est.
                      label: 'Progression du vocal',
                      value: '${_mmss(_position)} sur ${_mmss(duree)}',
                      child: LayoutBuilder(
                        builder: (context, contraintes) => GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (details) => unawaited(
                            _allerA(
                              details.localPosition.dx / contraintes.maxWidth,
                            ),
                          ),
                          child: SizedBox(
                            height: 28,
                            width: double.infinity,
                            child: CustomPaint(
                              painter: _FormeOnde(
                                valeurs: _formeOnde,
                                avancement: avancement,
                                couleur: couleur,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _BoutonVitesse(
                vitesse: ref.watch(vitesseVocalProvider),
                couleur: couleur,
                onTap: _vitesseSuivante,
              ),
            ],
          ),
          // Sous la silhouette et non sous le bouton : c'est d'elle
          // qu'elle parle.
          Padding(
            padding: const EdgeInsets.only(left: 48),
            child: Text(
              _position > Duration.zero
                  ? '${_mmss(_position)} / ${_mmss(duree)}'
                  : _mmss(duree),
              style: theme.textTheme.bodySmall?.copyWith(
                color: couleur,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ce qu'on dit quand le vocal est bien arrivé mais ne se lit pas.
///
/// Sur le web, la cause la plus courante ne vient pas de Rempart : le vocal
/// est de l'AAC dans un M4A, et un navigateur sans codec propriétaire refuse
/// de le décoder. Mesuré : Opera sous Linux rend une chaîne vide à
/// `canPlayType('audio/mp4; codecs="mp4a.40.2"')` là où Chrome rend
/// « probably ». Dire « vocal illisible » ferait accuser le message, qui est
/// intact et s'écoute ailleurs.
final _echecDeLecture =
    estWeb ? 'Ce navigateur ne lit pas ce format' : 'Vocal illisible';

/// Le cran de vitesse, en bout de bulle.
///
/// Sur la même ligne que la lecture et la silhouette : les trois commandes du
/// vocal se tiennent alors d'un bord à l'autre, au lieu d'en reléguer une sous
/// la durée, où elle passait pour une annotation.
///
/// Discret tant qu'on n'y touche pas : un vocal s'écoute d'abord, la vitesse
/// n'est qu'un recours. D'où une pastille teintée plutôt qu'un bouton, assez
/// large cependant pour être touchée sans viser.
class _BoutonVitesse extends StatelessWidget {
  const _BoutonVitesse({
    required this.vitesse,
    required this.couleur,
    required this.onTap,
  });

  final double vitesse;
  final Color couleur;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Lue seule, la pastille disait « x1 » : un nombre sans objet.
    return Semantics(
      button: true,
      label: 'Vitesse de lecture',
      value: libelleVitesseVocal(vitesse),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: couleur.withValues(alpha: vitesse == 1 ? 0.12 : 0.24),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Text(
                libelleVitesseVocal(vitesse),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: couleur,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Silhouette du son, façon barres verticales.
///
/// Le dessin est fait ici et non par un paquet : c'est une trentaine de lignes,
/// contre une dépendance de plus à suivre pour un rectangle par barre.
///
/// Les barres déjà écoutées sont pleines, les autres estompées : c'est ce qui
/// tient lieu de barre de progression, sans en ajouter une seconde.
class _FormeOnde extends CustomPainter {
  const _FormeOnde({
    required this.valeurs,
    required this.avancement,
    required this.couleur,
  });

  /// Amplitudes entre 0 et 1024. Vide, on dessine une ligne régulière : un
  /// vocal venu d'un autre client reste ainsi lisible et cliquable.
  final List<int> valeurs;
  final double avancement;
  final Color couleur;

  static const _largeurBarre = 3.0;
  static const _espace = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final pas = _largeurBarre + _espace;
    final nombre = (size.width / pas).floor().clamp(1, 200);
    final peintre = Paint()..strokeCap = StrokeCap.round;
    final milieu = size.height / 2;

    for (var i = 0; i < nombre; i++) {
      // Rééchantillonnage à la volée : la silhouette reçue n'a aucune raison
      // de compter exactement le nombre de barres qui tiennent à l'écran.
      final valeur = valeurs.isEmpty
          ? 0.35
          : valeurs[(i * valeurs.length / nombre).floor().clamp(
                0,
                valeurs.length - 1,
              )] /
              1024;
      // Un minimum visible : une barre de hauteur nulle ferait un trou dans la
      // silhouette, qu'on lirait comme un défaut d'affichage.
      final hauteur = (valeur * size.height).clamp(3.0, size.height);
      final x = i * pas + _largeurBarre / 2;
      peintre
        ..color = (i / nombre) <= avancement
            ? couleur
            : couleur.withValues(alpha: 0.35)
        ..strokeWidth = _largeurBarre;
      canvas.drawLine(
        Offset(x, milieu - hauteur / 2),
        Offset(x, milieu + hauteur / 2),
        peintre,
      );
    }
  }

  @override
  bool shouldRepaint(_FormeOnde ancien) =>
      ancien.avancement != avancement ||
      ancien.couleur != couleur ||
      ancien.valeurs != valeurs;
}

/// Les médias d'un même envoi, en mosaïque.
///
/// Deux par ligne, comme sur les autres messageries : au-delà, une photo de
/// téléphone devient une vignette qu'on ne reconnaît plus. Le dernier d'un
/// nombre impair prend toute la largeur, ce qui évite un trou à droite.
class _GrilleAlbum extends StatelessWidget {
  const _GrilleAlbum({required this.evenements});

  final List<matrix.Event> evenements;

  /// Au-delà, on n'affiche plus : la grille dirait « +7 » sur la dernière
  /// case. Vingt photos en mosaïque ne se regardent pas, elles se parcourent.
  static const _maxVisibles = 6;

  @override
  Widget build(BuildContext context) {
    final visibles = evenements.take(_maxVisibles).toList();
    final restants = evenements.length - visibles.length;

    final lignes = <List<matrix.Event>>[];
    for (var i = 0; i < visibles.length; i += 2) {
      lignes.add(visibles.sublist(i, math.min(i + 2, visibles.length)));
    }

    return SizedBox(
      width: 240,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final ligne in lignes)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  for (final evenement in ligne) ...[
                    Expanded(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _ImageJointe(event: evenement, enGrille: true),
                            // Le compte des non-affichées se pose sur la
                            // dernière case visible, pas à côté : c'est là
                            // qu'on le cherche.
                            if (restants > 0 &&
                                evenement == visibles.last)
                              ColoredBox(
                                color: Colors.black.withValues(alpha: 0.45),
                                child: Center(
                                  child: Text(
                                    '+$restants',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (evenement != ligne.last) const SizedBox(width: 3),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
