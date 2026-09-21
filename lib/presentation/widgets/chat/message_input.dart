import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../../../app/theme.dart';
import '../../../core/mouvement.dart';
import '../../../core/plateforme.dart';
import '../../../core/utils/continuer_liste.dart';
import '../../../data/models/bot.dart';
import '../../../data/models/matrix_extensions.dart';
import '../../../data/services/enregistreur_vocal.dart';
import '../adaptive/adaptive.dart';

/// Barre de saisie de message
class MessageInput extends StatefulWidget {
  const MessageInput({
    required this.onSend,
    this.commandes = const <BotCommand>[],
    super.key,
    this.replyTo,
    this.onCancelReply,
    this.onAttachmentPressed,
    this.onTyping,
    this.room,
    this.onVocal,
    this.enabled = true,
  });

  final Function(String message) onSend;

  /// Commandes declarees par le bot d'en face, proposees des la frappe du « / ».
  /// Vide pour une conversation entre personnes : rien ne surgit alors.
  final List<BotCommand> commandes;
  final matrix.Event? replyTo;
  final VoidCallback? onCancelReply;
  final VoidCallback? onAttachmentPressed;

  /// Signale que l'utilisateur est (ou n'est plus) en train d'écrire.
  final void Function({required bool actif})? onTyping;

  /// Room courante, pour proposer ses membres après un « @ ».
  final matrix.Room? room;

  /// Envoi d'un message vocal. Absent, le bouton micro reste éteint plutôt que
  /// de faire mine d'enregistrer.
  final void Function(VocalEnregistre vocal)? onVocal;

  final bool enabled;

  @override
  State<MessageInput> createState() => _MessageInputState();
}

/// Encombrement d'un bouton de la barre de saisie.
///
/// 40 points : la cible reste confortable au doigt, sans les 48 points qu'un
/// `IconButton` se reserve d'office et qui creusaient un vide entre le menu,
/// la piece jointe et le champ.
/// Encombrement des boutons plats de la barre (commandes, pièce jointe).
///
/// 40 de large, resserré : un `IconButton` s'en réserve 48 d'office, et deux
/// côte à côte creusaient un vide au bord de la barre. C'est cette largeur,
/// avec un `padding` nul, qui les rapproche, et non la densité visuelle.
///
/// 48 de haut, comme le bouton d'envoi : la rangée s'aligne sur le bas, pour
/// que les boutons restent en bas quand le message grandit sur plusieurs
/// lignes, et une boîte plus courte que ses voisines y descend d'autant. Les
/// icônes se retrouvaient cinq points sous le texte.
///
/// Piège qui a coûté un aller-retour : `VisualDensity.compact` **retranche
/// huit points** aux deux minimums (`effectiveConstraints`). Demander 48 de
/// haut avec elle en donnait 40, et le décalage restait entier. La densité
/// est donc retirée, la largeur étant déjà tenue par `minWidth`.
/// `test/barre_saisie_alignement_test.dart` mesure le résultat.
const _tailleBouton = BoxConstraints(minWidth: 40, minHeight: 48);

class _MessageInputState extends State<MessageInput> {
  final _controller = TextEditingController();
  // Le nœud porte lui-même l'écoute du clavier : un `Focus` autour du champ
  // ferait la même chose en ajoutant un cran d'imbrication.
  late final _focusNode = FocusNode()..onKeyEvent = _surToucheClavier;
  bool _hasText = false;

  /// Extinction automatique : sans elle, quitter le champ sans envoyer
  /// laisserait le contact devant un « en train d'écrire » perpétuel.
  Timer? _finDeSaisie;
  bool _saisieSignalee = false;
  DateTime? _dernierSignal;

  /// Membres proposés pour la mention en cours, vide hors mention.
  List<matrix.User> _mentions = const [];
  List<BotCommand> _commandes = const [];

  /// Enregistrement en cours : la barre entière se transforme.
  bool _enregistre = false;

  /// Rafraîchit le chronomètre affiché. Une seconde suffit : c'est la
  /// précision qu'on montre.
  Timer? _chrono;
  Duration _duree = Duration.zero;

  @override
  void dispose() {
    _chrono?.cancel();
    // L'écran disparaît pendant un enregistrement : le micro doit se relâcher,
    // sinon il reste pris par l'application (voyant allumé sur Android).
    if (_enregistre) unawaited(EnregistreurVocal.instance.annuler());
    _finDeSaisie?.cancel();
    // Fermer le fil proprement : l'écran disparaît, l'autre ne doit pas rester
    // avec l'indicateur allumé.
    if (_saisieSignalee) {
      widget.onTyping?.call(actif: false);
    }
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
    _signalerSaisie(actif: hasText);
    _majMentions();
    _majCommandes();
  }

  /// Commande en cours de frappe, ou null.
  ///
  /// Contrairement au « @ », le « / » n'a de sens qu'en TETE de message : une
  /// commande n'est jamais au milieu d'une phrase, et une date « 12/09 » ou une
  /// URL feraient sinon surgir la liste a chaque frappe.
  RegExpMatch? _commandeEnCours() {
    final selection = _controller.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;
    final avant = _controller.text.substring(0, selection.baseOffset);
    return RegExp(r'^/([a-zA-Z_]*)$').firstMatch(avant);
  }

  void _majCommandes() {
    final motif = _commandeEnCours();
    if (widget.commandes.isEmpty || motif == null) {
      if (_commandes.isNotEmpty) setState(() => _commandes = const []);
      return;
    }
    final debut = (motif.group(1) ?? '').toLowerCase();
    setState(() => _commandes = widget.commandes
        .where((c) => c.commande.toLowerCase().startsWith('/$debut'))
        .take(6)
        .toList());
  }

  void _choisirCommande(BotCommand c) {
    // La commande REMPLACE la ligne : elle en occupait deja tout le debut.
    final jeton = c.commande.split(' ').first; // « /echo <texte> » -> « /echo »
    _controller.value = TextEditingValue(
      text: '$jeton ',
      selection: TextSelection.collapsed(offset: jeton.length + 1),
    );
    setState(() => _commandes = const []);
  }

  Widget _listeCommandes(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 1),
          for (final c in _commandes)
            ListTile(
              dense: true,
              title: Text(c.commande,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: c.description.isEmpty ? null : Text(c.description),
              onTap: () => _choisirCommande(c),
            ),
        ],
      ),
    );
  }

  /// Mot en cours de frappe après un « @ », ou null.
  ///
  /// Le « @ » doit ouvrir un mot : sans ce garde, une adresse e-mail tapée
  /// dans le message ferait surgir la liste des membres.
  RegExpMatch? _mentionEnCours() {
    final selection = _controller.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;
    final avant = _controller.text.substring(0, selection.baseOffset);
    return RegExp(r'(?:^|\s)@([^\s@]*)$').firstMatch(avant);
  }

  void _majMentions() {
    final room = widget.room;
    final motif = _mentionEnCours();
    if (room == null || motif == null) {
      if (_mentions.isNotEmpty) setState(() => _mentions = const []);
      return;
    }
    final debut = (motif.group(1) ?? '').toLowerCase();
    final trouves = room
        .getParticipants()
        .where((membre) => membre.id != room.client.userID)
        .where(
          (membre) =>
              debut.isEmpty ||
              membre.calcDisplayname().toLowerCase().contains(debut) ||
              membre.id.toLowerCase().contains(debut),
        )
        .take(5)
        .toList();
    setState(() => _mentions = trouves);
  }

  /// Insère la mention au format attendu par le SDK.
  ///
  /// `Room.sendTextEvent` reconstruit `m.mentions` en relisant le texte : il
  /// attend « @Nom », ou « @[Nom avec espaces] » (voir `User.mentionFragments`).
  /// Écrire le nom autrement enverrait un simple texte, que le bot ne verrait
  /// pas comme une interpellation.
  void _choisirMention(matrix.User membre) {
    final motif = _mentionEnCours();
    if (motif == null) return;
    final nom = membre.calcDisplayname();
    final jeton = RegExp(r'^\w+$').hasMatch(nom) ? '@$nom' : '@[$nom]';
    final texte = _controller.text;
    final debutJeton = motif.start + (motif.group(0)!.startsWith('@') ? 0 : 1);
    final nouveau = texte.replaceRange(
        debutJeton, _controller.selection.baseOffset, '$jeton ');
    _controller.value = TextEditingValue(
      text: nouveau,
      selection: TextSelection.collapsed(offset: debutJeton + jeton.length + 1),
    );
    setState(() => _mentions = const []);
  }

  Widget _listeMentions(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 1),
          for (final membre in _mentions)
            ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 16,
                child: Text(
                  membre.calcDisplayname().characters.take(1).toString(),
                ),
              ),
              title: Text(membre.calcDisplayname()),
              onTap: () => _choisirMention(membre),
            ),
        ],
      ),
    );
  }

  /// Tient Matrix informé de la saisie, sans inonder le serveur.
  ///
  /// Le serveur oublie l'état au bout de 30 s : on le rafraîchit donc toutes
  /// les 15 s tant que la frappe continue, et on l'éteint après 5 s d'inaction.
  void _signalerSaisie({required bool actif}) {
    final signaler = widget.onTyping;
    if (signaler == null) return;

    if (!actif) {
      _finDeSaisie?.cancel();
      if (_saisieSignalee) {
        _saisieSignalee = false;
        signaler(actif: false);
      }
      return;
    }

    final maintenant = DateTime.now();
    final expire = _dernierSignal == null ||
        maintenant.difference(_dernierSignal!) > const Duration(seconds: 15);
    if (!_saisieSignalee || expire) {
      _saisieSignalee = true;
      _dernierSignal = maintenant;
      signaler(actif: true);
    }

    _finDeSaisie?.cancel();
    _finDeSaisie = Timer(
      const Duration(seconds: 5),
      () => _signalerSaisie(actif: false),
    );
  }

  /// Entrée envoie, Maj+Entrée passe à la ligne, mais seulement au clavier.
  ///
  /// C'est ce que font tous les clients de bureau, et ce qu'attend une main
  /// posée sur un clavier : sans cela, il fallait viser le bouton d'envoi à la
  /// souris après chaque phrase. Sur un téléphone, la touche Entrée du clavier
  /// virtuel reste un retour à la ligne : elle y est le seul moyen d'écrire un
  /// message en deux paragraphes, et le bouton d'envoi est déjà sous le pouce.
  ///
  /// Corollaire sur le web : la poursuite automatique des listes à puces
  /// s'obtient par Maj+Entrée, le passage à la ligne étant devenu son geste.
  KeyEventResult _surToucheClavier(FocusNode node, KeyEvent evenement) {
    if (!estWeb || evenement is! KeyDownEvent) return KeyEventResult.ignored;
    final touche = evenement.logicalKey;
    if (touche != LogicalKeyboardKey.enter &&
        touche != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) return KeyEventResult.ignored;
    _sendMessage();
    // Retenue, sans quoi le retour à la ligne s'insérerait par-dessus le
    // marché et laisserait un champ vide d'une ligne de haut.
    return KeyEventResult.handled;
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    widget.onSend(text);
    _controller.clear();
    setState(() => _hasText = false);
    // Le message est parti : l'indicateur n'a plus lieu d'être.
    _signalerSaisie(actif: false);
  }

  /// Feuille des commandes du bot.
  ///
  /// Une commande sans argument part tout de suite : c'est ce qu'on attend en
  /// la choisissant dans une liste. Une commande qui en attend un
  /// (`/echo <texte>`) est au contraire posée dans le champ, curseur prêt,
  /// car l'envoyer telle quelle vaudrait un message vide.
  Future<void> _ouvrirCommandes() async {
    final commandes = widget.commandes;
    if (commandes.isEmpty) return;

    final choisie = await feuilleAdaptative<BotCommand>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final commande in commandes)
              ListTile(
                leading: const Icon(Icons.chevron_right),
                title: Text(
                  commande.commande,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                subtitle: commande.description.isEmpty
                    ? null
                    : Text(commande.description),
                onTap: () => Navigator.pop(context, commande),
              ),
          ],
        ),
      ),
    );
    if (choisie == null || !mounted) return;

    // Un argument attendu se reconnaît à ses chevrons, la convention des
    // catalogues de commandes.
    final attendUnArgument = choisie.commande.contains('<');
    if (attendUnArgument) {
      final base = choisie.commande.split('<').first.trimRight();
      _controller.text = '$base ';
      _controller.selection =
          TextSelection.collapsed(offset: _controller.text.length);
      _focusNode.requestFocus();
      setState(() => _hasText = true);
      return;
    }
    widget.onSend(choisie.commande);
  }

  Future<void> _demarrerEnregistrement() async {
    final ok = await EnregistreurVocal.instance.demarrer();
    if (!mounted) return;
    if (!ok) {
      // Permission refusée, ou micro indisponible. Le dire : un bouton qui ne
      // répond pas passe pour une panne de Rempart.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Micro indisponible. Autorisez l'accès au micro dans les "
            'réglages de votre téléphone.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _enregistre = true;
      _duree = Duration.zero;
    });
    _chrono = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _duree = EnregistreurVocal.instance.ecoule);
    });
  }

  Future<void> _annulerEnregistrement() async {
    _chrono?.cancel();
    await EnregistreurVocal.instance.annuler();
    if (mounted) setState(() => _enregistre = false);
  }

  Future<void> _terminerEnregistrement() async {
    _chrono?.cancel();
    final vocal = await EnregistreurVocal.instance.arreter();
    if (!mounted) return;
    setState(() => _enregistre = false);
    if (vocal == null) {
      // Trop court : l'appui a glissé, ou on s'est ravisé aussitôt. Rien à
      // envoyer, et rien à reprocher.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message vocal trop court')),
      );
      return;
    }
    widget.onVocal?.call(vocal);
  }

  /// La barre pendant l'enregistrement : abandonner, le temps écoulé, envoyer.
  ///
  /// Un appui pour commencer, un appui pour envoyer, plutôt que le doigt
  /// maintenu de WhatsApp : rien ne se perd si la main bouge, et un long
  /// message ne demande pas de tenir l'écran pendant une minute.
  Widget _barreEnregistrement(BuildContext context) {
    final theme = Theme.of(context);
    final minutes = _duree.inMinutes.toString().padLeft(2, '0');
    final secondes = (_duree.inSeconds % 60).toString().padLeft(2, '0');

    return Row(
      children: [
        IconButton(
          onPressed: _annulerEnregistrement,
          icon: const Icon(Icons.delete_outline),
          color: theme.colorScheme.error,
          tooltip: "Abandonner l'enregistrement",
        ),
        const SizedBox(width: 4),
        // Le point rouge dit que le micro est ouvert, en un coup d'oeil.
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: theme.colorScheme.error,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '$minutes:$secondes',
          style: theme.textTheme.titleMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const Spacer(),
        Text(
          'Enregistrement...',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(width: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: RempartTokens.ombreLegere(theme.brightness),
          ),
          child: IconButton.filled(
            onPressed: _terminerEnregistrement,
            icon: const Icon(Icons.arrow_upward_rounded),
            tooltip: 'Envoyer',
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      // `top: false` : le corps passe sous la barre du haut, donc la zone sûre
      // inclut la barre d'état. Sans cette précision, la saisie se réservait
      // 44 points de vide au-dessus du champ.
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            RempartTokens.espaceS,
            RempartTokens.espaceXs,
            RempartTokens.espaceS,
            RempartTokens.espaceS,
          ),
          // Capsule posée sur le fil, comme les pastilles du haut : le fond
          // continue de vivre autour d'elle, et les messages passent dessous.
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.72 : 0.82,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.7),
                  ),
                  boxShadow: RempartTokens.ombreDouce(theme.brightness),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Membres proposés après un « @ »
                    if (_mentions.isNotEmpty) _listeMentions(context),
                    if (_commandes.isNotEmpty) _listeCommandes(context),

                    // Prévisualisation de la réponse
                    if (widget.replyTo != null) _buildReplyPreview(context),

                    // Barre de saisie
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: RempartTokens.espaceXs,
                      ),
                      child: _enregistre
                          ? _barreEnregistrement(context)
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                // Menu des commandes, devant la pièce jointe : dans une
                                // conversation avec un bot, c'est ce qu'on cherche le plus
                                // souvent. Absent ailleurs, où il n'aurait rien à montrer.
                                if (widget.commandes.isNotEmpty)
                                  IconButton(
                                    onPressed: widget.enabled
                                        ? _ouvrirCommandes
                                        : null,
                                    icon: const Icon(Icons.menu),
                                    tooltip: 'Commandes',
                                    color: colorScheme.onSurfaceVariant,
                                    constraints: _tailleBouton,
                                    padding: EdgeInsets.zero,
                                  ),

                                // Bouton pièce jointe
                                IconButton(
                                  onPressed: widget.enabled
                                      ? widget.onAttachmentPressed
                                      : null,
                                  icon: const Icon(Icons.attach_file),
                                  color: colorScheme.onSurfaceVariant,
                                  constraints: _tailleBouton,
                                  padding: EdgeInsets.zero,
                                ),

                                // Champ de texte, à même la capsule : un second fond
                                // arrondi dans un fond arrondi fait boîte dans la boîte.
                                Expanded(
                                  child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxHeight: 120),
                                    child: TextField(
                                      controller: _controller,
                                      focusNode: _focusNode,
                                      enabled: widget.enabled,
                                      // Une liste se poursuit toute seule : passer à la
                                      // ligne depuis « - sucrine » ouvre la puce suivante,
                                      // et un second passage sur une puce vide la retire.
                                      inputFormatters: const [ContinuerListe()],
                                      onChanged: (_) => _onTextChanged(),
                                      onSubmitted: (_) => _sendMessage(),
                                      maxLines: null,
                                      textCapitalization:
                                          TextCapitalization.sentences,
                                      decoration: const InputDecoration(
                                        hintText: 'Message...',
                                        // Le fond arrondi est celui du conteneur : le
                                        // remplissage du thème, lui, se dessine en
                                        // rectangle dès que la bordure est retirée, et
                                        // carrait les extrémités du champ.
                                        filled: false,
                                        // Le champ n'a pas de bordure propre : c'est le
                                        // conteneur qui la porte. Sans ces trois lignes,
                                        // celle du thème se superpose au focus et double
                                        // le trait.
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        // Le bouton voisin porte deja son propre
                                        // espacement : en remettre autant a l'horizontale
                                        // eloignait le texte de son trombone sans raison.
                                        //
                                        // Le creux BAS ne se touche pas : la rangee
                                        // s'aligne sur le bas, ou le centre d'une icone
                                        // tombe a 24 du sol, et le centre du texte a
                                        // « creux bas + moitie de l'interligne ». Les deux
                                        // ne coincident qu'a 13.
                                        //
                                        // Le creux HAUT est passe de 15 a 12, et pas plus
                                        // bas. Sur une ligne il ne coute rien (la hauteur
                                        // vient des boutons, 48 points, et le decorateur
                                        // absorbe tout ce qui passe sous 12) ; sur
                                        // plusieurs, il pose une bande vide au-dessus de la
                                        // premiere ligne. Mesure a l'appui : 12 laisse le
                                        // texte exactement la ou 15 le laissait, 9 le
                                        // decale d'un point et 6 de trois et demi, ce que
                                        // `barre_saisie_alignement_test` refuse.
                                        contentPadding: EdgeInsets.fromLTRB(
                                          RempartTokens.espaceXs,
                                          12,
                                          RempartTokens.espaceXs,
                                          13,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(width: 8),

                                // Bouton envoyer : le micro devient un bouton plein dès
                                // qu'il y a quelque chose à envoyer. Le fondu évite le
                                // clignotement à chaque première lettre.
                                AnimatedSwitcher(
                                  duration: dureeAnimation(
                                    context,
                                    const Duration(milliseconds: 180),
                                  ),
                                  transitionBuilder: (enfant, animation) =>
                                      ScaleTransition(
                                    scale: animation,
                                    child: FadeTransition(
                                        opacity: animation, child: enfant),
                                  ),
                                  child: _hasText
                                      ? DecoratedBox(
                                          key: const ValueKey('envoyer'),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            boxShadow:
                                                RempartTokens.ombreLegere(
                                                    theme.brightness),
                                          ),
                                          child: IconButton.filled(
                                            onPressed: widget.enabled
                                                ? _sendMessage
                                                : null,
                                            icon: const Icon(
                                                Icons.arrow_upward_rounded),
                                            tooltip: 'Envoyer',
                                          ),
                                        )
                                      : DecoratedBox(
                                          key: const ValueKey('micro'),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            boxShadow:
                                                RempartTokens.ombreLegere(
                                                    theme.brightness),
                                          ),
                                          child: IconButton.filled(
                                            onPressed: widget.enabled &&
                                                    widget.onVocal != null &&
                                                    EnregistreurVocal
                                                        .instance.disponible
                                                ? _demarrerEnregistrement
                                                : null,
                                            icon: const Icon(
                                                Icons.mic_none_rounded),
                                            tooltip: 'Message vocal',
                                          ),
                                        ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReplyPreview(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final replyTo = widget.replyTo!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // `nomLisibleDeLExpediteur` : `senderDisplayName` retombe
                  // sur le localpart, et la barre annonçait « Réponse à
                  // u_fd8de5c7… ». Tronqué sur une ligne : le nom vient d'un
                  // tiers, et rien ne borne un display name Matrix.
                  'Réponse à '
                  '${replyTo.nomLisibleDeLExpediteur ?? 'Contact inconnu'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  replyTo.texteApercu,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // Même rôle que la citation dans la bulle : c'est le même
                  // aperçu, il était à 13 ici et à 12 là-bas.
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: widget.onCancelReply,
            icon: const Icon(Icons.close, size: 20),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
