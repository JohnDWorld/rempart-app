import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../../../app/theme.dart';
import '../../../core/plateforme.dart';
import '../../../data/models/matrix_extensions.dart';
import '../../../data/providers/mode_theme.dart';
import '../../../data/providers/providers.dart';
import '../../../data/services/archive_service.dart';
import '../../../services/auth_service.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/common/logo_rempart.dart';
import '../../widgets/common/recovery_key_dialog.dart';
import '../../widgets/conversations/conversation_tile.dart';
import '../../widgets/settings/verification_appareil.dart';

/// Écran principal affichant la liste des conversations (rooms Matrix)
class ConversationsScreen extends ConsumerStatefulWidget {
  const ConversationsScreen({super.key, this.deuxColonnes = false});

  /// Vrai quand la conversation s'ouvre **à côté** de la liste, sur un écran
  /// large, plutôt que par-dessus. Toucher une conversation change alors le
  /// panneau voisin au lieu d'empiler un écran.
  final bool deuxColonnes;

  @override
  ConsumerState<ConversationsScreen> createState() =>
      _ConversationsScreenState();
}

class _ConversationsScreenState extends ConsumerState<ConversationsScreen>
    with WidgetsBindingObserver {
  bool _isConnecting = false;
  String? _connectionError;

  final _rechercheController = TextEditingController();
  String _recherche = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Tenter la connexion Matrix au démarrage et rafraîchir les rooms
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectToMatrix();
      // Toujours forcer un rafraîchissement au démarrage/retour
      _refreshRooms();
      unawaited(_maybeShowRecoveryKey());
      unawaited(_confirmerLaSession());
    });
  }

  @override
  void dispose() {
    _rechercheController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Rafraîchir quand l'app revient au premier plan
    if (state == AppLifecycleState.resumed) {
      _refreshRooms();
    }
  }

  /// Force le rafraîchissement de la liste des rooms
  Future<void> _refreshRooms() async {
    debugPrint('ConversationsScreen: Rafraîchissement des rooms');
    // Forcer d'abord un rebuild pour afficher l'état actuel
    ref.read(matrixStateNotifierProvider.notifier).state++;

    // Puis synchroniser avec le serveur
    final matrixService = ref.read(matrixServiceProvider);
    await matrixService.syncNow();

    // Et rafraîchir à nouveau après sync
    if (mounted) {
      ref.read(matrixStateNotifierProvider.notifier).state++;
    }
  }

  /// Connexion/inscription à Matrix via le chemin d'auth unifié.
  Future<void> _connectToMatrix() async {
    if (_isConnecting) return;

    // Récupérer l'utilisateur Supabase
    final user = ref.read(authServiceProvider).currentUser;
    if (user == null) return;

    setState(() {
      _isConnecting = true;
      _connectionError = null;
    });

    try {
      // Toujours passer par ensureMatrixSession, même si une session Matrix
      // existe déjà : elle seule vérifie que cette session appartient bien à
      // l'utilisateur Supabase courant. Court-circuiter sur `isLoggedIn`
      // réutilisait la session restaurée du compte précédent (fuite de
      // conversations d'un compte à l'autre).
      // Chemin d'auth Matrix unifié (username u_<uuid> + mot de passe aléatoire)
      await ref.read(authServiceProvider).ensureMatrixSession(user);

      // Notifier les providers que l'état Matrix a changé
      if (mounted) {
        ref.read(matrixStateNotifierProvider.notifier).state++;
      }
    } catch (e) {
      debugPrint('Erreur connexion Matrix: $e');
      if (mounted) {
        setState(() {
          _connectionError = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  /// Fait confirmer cette session par un appareil déjà connu, si besoin.
  ///
  /// Le cas est celui d'une connexion par QR code : elle n'a jamais vu le mot
  /// de passe, qui est aussi la phrase secrète du coffre SSSS. Elle ne peut
  /// donc pas l'ouvrir, reste non signée, et le SDK refuse alors d'aller
  /// chercher la moindre clé dans la sauvegarde en ligne. Résultat sans cette
  /// demande : « The sender has not sent us the session key » sur la totalité
  /// des messages, y compris ceux dont la clé dort sur le serveur.
  Future<void> _confirmerLaSession() async {
    // Le durcissement E2E, quand il a lieu (connexion par mot de passe), signe
    // la session tout seul. Attendre évite de déranger un autre appareil pour
    // une question qui allait se résoudre seule.
    await ref.read(authServiceProvider).awaitE2eSetup();

    final matrixService = ref.read(matrixServiceProvider);
    // Les clés du compte n'arrivent qu'avec les premières synchronisations :
    // demandées trop tôt, elles sont absentes et la session se croirait à
    // tort seule au monde. On repose donc la question quelques fois.
    for (var essai = 0; essai < 10; essai++) {
      if (!mounted) return;
      final verification = await matrixService.demanderConfirmationDeSession();
      if (verification != null) {
        if (!mounted) return;
        await ouvrirVerification(verification, nousAvonsDemande: true);
        return;
      }
      // Session déjà signée : il n'y a rien à confirmer, ni maintenant ni
      // plus tard.
      if (matrixService.client?.isUnknownSession == false) return;
      await Future.delayed(const Duration(seconds: 3));
    }
  }

  /// Affiche une seule fois la recovery key E2E après un nouveau setup.
  ///
  /// Le durcissement E2E tourne en tâche de fond (voir AuthService), donc on
  /// attend qu'il soit prêt : la clé peut arriver quelques secondes après
  /// l'affichage de l'écran, sans avoir bloqué la navigation.
  Future<void> _maybeShowRecoveryKey() async {
    final auth = ref.read(authServiceProvider);
    // Attendre la fin du durcissement E2E en fond, puis n'afficher (et ne
    // consommer) la clé que si l'écran est toujours monté.
    await auth.awaitE2eSetup();
    if (!mounted) return;
    final recoveryKey = auth.consumePendingRecoveryKey();
    if (recoveryKey != null) {
      unawaited(showRecoveryKeyDialog(context, recoveryKey));
    }
  }

  /// Le menu de l'écran, posé à gauche de la recherche.
  ///
  /// Trois traits sur un écran large : la barre d'onglets du bas n'y existe
  /// plus et c'est devenu le seul menu de l'application, « Paramètres »
  /// compris. Trois points sur un téléphone, où il ne donne accès qu'à trois
  /// entrées de plus, et où les trois traits promettraient un panneau
  /// entier : l'onglet du bas montre déjà les paramètres, et le redire ici
  /// ferait deux chemins pour un même écran.
  Widget _boutonMenu(BuildContext context) {
    // `adaptive.more` : trois points verticaux sur Android, horizontaux sur
    // iPhone, chacun selon la convention de son système.
    final icone = widget.deuxColonnes ? Icons.menu : Icons.adaptive.more;
    if (estIOS) {
      return IconButton(
        icon: Icon(icone),
        tooltip: 'Menu',
        onPressed: _showMenu,
      );
    }
    return PopupMenuButton<String>(
      icon: Icon(icone),
      tooltip: 'Menu',
      position: PopupMenuPosition.under,
      onSelected: _ouvrirEntreeMenu,
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'my-bots',
          child: ListTile(
            leading: Icon(Icons.smart_toy_outlined),
            title: Text('Mes bots'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'archives',
          child: ListTile(
            leading: Icon(Icons.archive_outlined),
            title: Text('Archives'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'theme',
          child: ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('Apparence'),
            subtitle: Text(libelleModeTheme(ref.read(modeThemeProvider))),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (widget.deuxColonnes) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'settings',
            child: ListTile(
              leading: Icon(Icons.settings_outlined),
              title: Text('Paramètres'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _ouvrirEntreeMenu(String valeur) async {
    switch (valeur) {
      case 'my-bots':
        await context.push('/my-bots');
      case 'archives':
        await context.push('/archives');
      case 'settings':
        await context.push('/settings');
      case 'theme':
        await _choisirTheme();
    }
  }

  void _showMenu() {
    if (estIOS) {
      unawaited(_showCupertinoMenu());
    } else {
      _showMaterialMenu();
    }
  }

  Future<void> _showCupertinoMenu() async {
    final value = await showAdaptiveActionSheet<String>(
      context: context,
      actions: [
        const AdaptiveAction(
          label: 'Archives',
          value: 'archives',
          icon: Icon(CupertinoIcons.archivebox),
        ),
        const AdaptiveAction(
          label: 'Mes bots',
          value: 'my-bots',
          icon: Icon(CupertinoIcons.desktopcomputer),
        ),
        const AdaptiveAction(
          label: 'Apparence',
          value: 'theme',
          icon: Icon(CupertinoIcons.circle_lefthalf_fill),
        ),
        if (widget.deuxColonnes)
          const AdaptiveAction(
            label: 'Paramètres',
            value: 'settings',
            icon: Icon(CupertinoIcons.settings),
          ),
      ],
      cancelAction: const AdaptiveAction(label: 'Annuler'),
    );
    if (!mounted) return;
    if (value == 'settings') {
      await context.push('/settings');
    } else if (value == 'archives') {
      await context.push('/archives');
    } else if (value == 'my-bots') {
      await context.push('/my-bots');
    } else if (value == 'theme') {
      await _choisirTheme();
    }
  }

  /// Choix clair / sombre / système.
  ///
  /// Une feuille et non un interrupteur : « suivre le système » est un état à
  /// part entière, qu'un simple bouton à deux positions ne sait pas dire.
  Future<void> _choisirTheme() async {
    final actuel = ref.read(modeThemeProvider);
    final choix = await feuilleAdaptative<ThemeMode>(
      context: context,
      builder: (contexteFeuille) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in ThemeMode.values)
              ListTile(
                leading: Icon(
                  switch (mode) {
                    ThemeMode.light => Icons.light_mode_outlined,
                    ThemeMode.dark => Icons.dark_mode_outlined,
                    ThemeMode.system => Icons.brightness_auto_outlined,
                  },
                ),
                title: Text(libelleModeTheme(mode)),
                trailing: mode == actuel ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(contexteFeuille, mode),
              ),
          ],
        ),
      ),
    );
    if (choix == null) return;
    ref.read(modeThemeProvider.notifier).state = choix;
    await enregistrerModeTheme(choix);
  }

  void _showMaterialMenu() {
    // Le menu Material est géré directement par PopupMenuButton dans le build
  }

  /// Afficher le dialogue de confirmation d'archivage
  Future<bool> _confirmArchiveConversation(
    BuildContext context,
    String roomName,
  ) async {
    if (estIOS) {
      return await showCupertinoDialog<bool>(
            context: context,
            builder: (context) => CupertinoAlertDialog(
              title: const Text('Archiver la conversation'),
              content: Text(
                'Voulez-vous archiver la conversation avec "$roomName" ? Vous pourrez la retrouver dans les archives.',
              ),
              actions: [
                CupertinoDialogAction(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Annuler'),
                ),
                CupertinoDialogAction(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Archiver'),
                ),
              ],
            ),
          ) ??
          false;
    } else {
      return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Archiver la conversation'),
              content: Text(
                'Voulez-vous archiver la conversation avec "$roomName" ? Vous pourrez la retrouver dans les archives.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Annuler'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Archiver'),
                ),
              ],
            ),
          ) ??
          false;
    }
  }

  /// Archiver une conversation (masquer localement)
  Future<void> _archiveConversation(matrix.Room room) async {
    try {
      await ArchiveService.instance.archiveRoom(room.id);

      // Forcer le rafraîchissement de la liste des rooms
      ref.read(matrixStateNotifierProvider.notifier).state++;

      if (mounted) {
        _showMessage(
          'Conversation avec "${nomAffichable(ref, room)}" archivée',
        );
      }
    } catch (e) {
      if (mounted) {
        _showMessage("Erreur lors de l'archivage: $e", isError: true);
      }
    }
  }

  /// Afficher le dialogue de confirmation de suppression.
  ///
  /// Le texte dit ce que Matrix fait vraiment : on quitte, sans que personne
  /// en soit averti. Le fil de l'autre reste intact et d'apparence vivante,
  /// alors que plus rien n'y circule dans notre direction. Tant que l'app
  /// n'affiche pas les événements d'appartenance dans le fil (voir le filtre
  /// de `chat_screen._messages`), le départ est littéralement invisible côté
  /// destinataire : le taire ici reviendrait à laisser croire à un effacement
  /// partagé.
  Future<bool> _confirmDeleteConversation(
    BuildContext context,
    matrix.Room room,
  ) async {
    final roomName = nomAffichable(ref, room);
    final message = room.otherUserMxid != null
        ? 'Vous quitterez la conversation et elle disparaîtra de votre '
            'liste.\n\n'
            'De son côté, $roomName conservera le fil et rien ne signalera '
            'votre départ : ce qui y sera écrit ensuite ne vous parviendra '
            'plus. Pour reprendre contact, ouvrez une nouvelle conversation.'
        : 'Vous quitterez « $roomName » et le groupe disparaîtra de votre '
            'liste.\n\n'
            "Il continuera d'exister sans vous, et vous ne recevrez plus "
            "rien de ce qui s'y dira. Il faudra une invitation pour y "
            'revenir.';
    if (estIOS) {
      return await showCupertinoDialog<bool>(
            context: context,
            builder: (context) => CupertinoAlertDialog(
              title: Text('Supprimer "$roomName"'),
              content: Text(message),
              actions: [
                CupertinoDialogAction(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Annuler'),
                ),
                CupertinoDialogAction(
                  isDestructiveAction: true,
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Supprimer'),
                ),
              ],
            ),
          ) ??
          false;
    } else {
      return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('Supprimer "$roomName"'),
              content: Text(message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Annuler'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Supprimer'),
                ),
              ],
            ),
          ) ??
          false;
    }
  }

  /// Supprimer une conversation : quitter la room (leave + forget).
  Future<void> _deleteConversation(matrix.Room room) async {
    final name = nomAffichable(ref, room);
    try {
      await ref.read(matrixServiceProvider).leaveRoom(room.id);
      // Nettoie un éventuel archivage local devenu obsolète.
      await ArchiveService.instance.unarchiveRoom(room.id);

      ref.read(matrixStateNotifierProvider.notifier).state++;

      if (mounted) {
        _showMessage('Conversation avec "$name" supprimée');
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Erreur lors de la suppression: $e', isError: true);
      }
    }
  }

  /// Affiche un message adaptatif (SnackBar sur Material, toast-like sur iOS)
  void _showMessage(String message, {bool isError = false}) {
    if (estIOS) {
      // Sur iOS, utiliser une overlay temporaire
      final overlay = OverlayEntry(
        builder: (context) => Positioned(
          bottom: MediaQuery.of(context).padding.bottom + 80,
          left: 16,
          right: 16,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isError
                    ? CupertinoColors.systemRed.darkColor
                    : CupertinoColors.systemGrey.darkColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                message,
                style: const TextStyle(color: CupertinoColors.white),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );

      Overlay.of(context).insert(overlay);
      Future.delayed(const Duration(seconds: 2), overlay.remove);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rooms = _filtrer(ref.watch(sortedRoomsProvider));
    final isMatrixConnected = ref.watch(matrixConnectionStateProvider);
    // `.value ?? false` : tant que le premier état de sync n'est pas connu, on
    // n'annonce pas une panne qui n'existe peut-être pas.
    final horsLigne = ref.watch(horsLigneProvider).value ?? false;

    return _buildEcran(rooms, isMatrixConnected, horsLigne);
  }

  /// Conversations retenues par la recherche.
  ///
  /// Filtrage local : la liste tient en mémoire, et interroger le serveur
  /// pour chaque lettre tapée serait aussi lent qu'inutile.
  List<matrix.Room> _filtrer(List<matrix.Room> rooms) {
    final q = _recherche.trim().toLowerCase();
    if (q.isEmpty) return rooms;
    return rooms
        .where((room) =>
            room.displayName.toLowerCase().contains(q) ||
            room.lastMessageText.toLowerCase().contains(q))
        .toList();
  }

  /// Champ de recherche, posé sous le titre.
  Widget _barreRecherche(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        // Le menu occupe la gauche en deux colonnes ; seul sur sa ligne, le
        // champ reprend la marge de la page.
        widget.deuxColonnes ? RempartTokens.espaceS : RempartTokens.espaceL,
        RempartTokens.espaceS,
        RempartTokens.espaceL,
        RempartTokens.espaceS,
      ),
      child: TextField(
        controller: _rechercheController,
        onChanged: (valeur) => setState(() => _recherche = valeur),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Rechercher une conversation',
          prefixIcon: const Icon(Icons.search, size: 22),
          isDense: true,
          suffixIcon: _recherche.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: 'Effacer',
                  onPressed: () {
                    _rechercheController.clear();
                    setState(() => _recherche = '');
                  },
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide(color: theme.colorScheme.primary),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  /// Tirer vers le bas pour forcer une synchronisation.
  ///
  /// Le SDK se rattrape déjà seul au retour du réseau ; ce geste sert à ne pas
  /// attendre, et à donner une réponse à qui doute que l'écran soit à jour.
  Future<void> _rafraichir() async {
    await ref.read(matrixServiceProvider).resynchroniser();
    if (!mounted) return;
    ref.read(matrixStateNotifierProvider.notifier).state++;
  }

  /// Bandeau « hors ligne », affiché au-dessus de la liste.
  ///
  /// Les conversations restent lisibles depuis la base locale : le bandeau dit
  /// seulement que rien de neuf n'arrivera tant que le serveur ne répond pas.
  /// Sans lui, une panne de réseau est indiscernable d'une absence de message.
  Widget _bandeauHorsLigne(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RempartTokens.espaceL,
        RempartTokens.espaceS,
        RempartTokens.espaceL,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: RempartTokens.espaceM,
          vertical: RempartTokens.espaceM,
        ),
        decoration: BoxDecoration(
          color: RempartTokens.alerte.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(RempartTokens.rayonChamp),
          border: Border.all(
            color: RempartTokens.alerte.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 18, color: RempartTokens.alerte),
            const SizedBox(width: RempartTokens.espaceS),
            Expanded(
              child: Text(
                'Hors ligne. Vos conversations restent consultables ; les '
                'nouveaux messages arriveront au retour du réseau.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// L'écran, identique sur les deux plateformes.
  ///
  /// La refonte visuelle a redessiné cette liste sans toucher a la variante
  /// Cupertino qui existait a cote : iOS gardait donc l'ancienne, sans
  /// recherche, sans filets et sans marge basse pour la barre d'onglets. Plutot
  /// que de peindre le nouveau dessin en double, on n'en garde qu'un : le
  /// design est une identite de marque, pas un habillage natif. Seules les
  /// INTERACTIONS restent adaptatives, la ou la convention compte vraiment.
  Widget _buildEcran(
      List<matrix.Room> rooms, bool isMatrixConnected, bool horsLigne) {
    return Scaffold(
      appBar: AppBar(
        // Deux en-têtes pour deux usages. Sur un écran large, la marque
        // devient le titre d'un panneau : centrée, sur deux lignes, elle a la
        // place de dire ce que Rempart est. Sur un téléphone, elle reste une
        // marque dans une barre : calée à gauche, sur une ligne, le menu à
        // l'autre bout, et la recherche a alors toute la sienne.
        centerTitle: widget.deuxColonnes,
        toolbarHeight: widget.deuxColonnes ? 78 : null,
        title: MarqueRempart(avecSousTitre: widget.deuxColonnes),
        actions: [if (!widget.deuxColonnes) _boutonMenu(context)],
      ),
      body: Column(
        children: [
          if (horsLigne) _bandeauHorsLigne(context),
          if (widget.deuxColonnes)
            // Une bande de fond à part pour le menu et la recherche : titre et
            // liste partagent le même fond, et sans elle les outils flottaient
            // entre les deux sans appartenir à l'un ni à l'autre. `surface`
            // est un cran plus clair que le fond dans les deux thèmes, et le
            // champ de recherche, plus soutenu encore, s'y détache toujours.
            ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: Row(
                children: [
                  const SizedBox(width: RempartTokens.espaceS),
                  _boutonMenu(context),
                  Expanded(child: _barreRecherche(context)),
                ],
              ),
            )
          else
            _barreRecherche(context),
          Expanded(
            child: !isMatrixConnected
                ? _buildNotConnectedState(context)
                : rooms.isEmpty
                    ? _buildEmptyState(context)
                    : RefreshIndicator.adaptive(
                        onRefresh: _rafraichir,
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          // 96 laisse passer la barre d'onglets flottante ;
                          // sans elle, ce serait un trou au bas de la liste.
                          padding: EdgeInsets.only(
                            bottom: widget.deuxColonnes ? 16 : 96,
                          ),
                          itemCount: rooms.length,
                          // Filet encarté, aligné sur le texte : d'un bord à
                          // l'autre il découpe la page en tranches ; ici il ne
                          // fait que séparer deux lignes.
                          separatorBuilder: (context, index) => const Divider(
                            height: 1,
                            indent: 84,
                            endIndent: RempartTokens.espaceL,
                          ),
                          itemBuilder: (context, index) {
                            final room = rooms[index];
                            return ConversationTile(
                              room: room,
                              onTap: () {
                                if (widget.deuxColonnes) {
                                  ref
                                      .read(selectedRoomIdProvider.notifier)
                                      .state = room.id;
                                  return;
                                }
                                context.push('/chat/${room.id}');
                              },
                              confirmArchive: () => _confirmArchiveConversation(
                                context,
                                nomAffichable(ref, room),
                              ),
                              onArchive: () => _archiveConversation(room),
                              confirmDelete: () => _confirmDeleteConversation(
                                context,
                                room,
                              ),
                              onDelete: () => _deleteConversation(room),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/new-chat'),
        tooltip: 'Nouvelle conversation',
        child: const Icon(Icons.edit_outlined),
      ),
    );
  }

  Widget _buildNotConnectedState(BuildContext context) {
    final isIOS = estIOS;
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isIOS
                  ? (_isConnecting
                      ? CupertinoIcons.cloud_upload
                      : CupertinoIcons.wifi_slash)
                  : (_isConnecting ? Icons.cloud_sync : Icons.cloud_off),
              size: 80,
              color: isIOS
                  ? CupertinoColors.systemGrey
                  : Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              _isConnecting ? 'Connexion en cours...' : 'Non connecté à Matrix',
              style: isIOS
                  ? TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? CupertinoColors.white
                          : CupertinoColors.black,
                    )
                  : Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _isConnecting
                  ? 'Veuillez patienter'
                  : 'La connexion au serveur de messagerie est requise',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isIOS
                    ? CupertinoColors.systemGrey
                    : Theme.of(context).colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
            if (_connectionError != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isIOS
                      ? CupertinoColors.systemRed.withValues(alpha: 0.1)
                      : Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _connectionError!.length > 150
                      ? '${_connectionError!.substring(0, 150)}...'
                      : _connectionError!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isIOS
                        ? CupertinoColors.systemRed
                        : Theme.of(context).colorScheme.onErrorContainer,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (_isConnecting && isIOS)
              const CupertinoActivityIndicator()
            else if (_isConnecting)
              const CircularProgressIndicator.adaptive()
            else if (isIOS)
              CupertinoButton.filled(
                onPressed: _connectToMatrix,
                child: const Text('Réessayer'),
              )
            else
              ElevatedButton.icon(
                onPressed: _connectToMatrix,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
          ],
        ),
      ),
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
            size: 80,
            color: isIOS
                ? CupertinoColors.systemGrey
                : Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'Aucune conversation',
            style: isIOS
                ? TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color:
                        isDark ? CupertinoColors.white : CupertinoColors.black,
                  )
                : Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Commencez une nouvelle conversation',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: isIOS
                  ? CupertinoColors.systemGrey
                  : Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 24),
          if (isIOS)
            CupertinoButton.filled(
              onPressed: () {
                context.push('/new-chat');
              },
              child: const Text('Nouveau message'),
            )
          else
            ElevatedButton.icon(
              onPressed: () {
                context.push('/new-chat');
              },
              icon: const Icon(Icons.add),
              label: const Text('Nouveau message'),
            ),
        ],
      ),
    );
  }
}
