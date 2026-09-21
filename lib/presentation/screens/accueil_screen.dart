import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/mouvement.dart';
import '../../core/plateforme.dart';
import '../../data/providers/providers.dart';
import '../../data/services/update_service.dart';
import '../widgets/settings/mise_a_jour.dart';
import 'chat/chat_screen.dart';
import 'conversations/conversations_screen.dart';
import 'settings/settings_screen.dart';

/// En dessous, la liste et la conversation ne tiennent pas ensemble : 360
/// pour la liste, et il faut au moins autant pour lire un fil.
///
/// C'est le même seuil que celui des feuilles modales, et ce n'est pas une
/// coïncidence : c'est là qu'on cesse de dessiner pour un téléphone.
const _seuilDeuxColonnes = RempartTokens.seuilEcranLarge;

/// Coque de l'application : les deux onglets et leur barre flottante.
///
/// Il y en avait trois : « Profil » redisait ce que « Paramètres » montrait
/// déjà, jusqu'à la fiche en tête d'écran. Trois entrées sur quatre y étaient
/// en double, et la quatrième (« Archives ») a rejoint les paramètres.
///
/// `IndexedStack` et non un remplacement d'écran : passer de Messages à
/// Profil et revenir doit retrouver la liste où on l'avait laissée, position
/// de défilement comprise.
class AccueilScreen extends StatefulWidget {
  const AccueilScreen({super.key});

  @override
  State<AccueilScreen> createState() => _AccueilScreenState();
}

class _AccueilScreenState extends State<AccueilScreen>
    with WidgetsBindingObserver {
  int _onglet = 0;

  /// Hauteur de la barre elle-même. La zone sûre du bas (barre de gestes)
  /// s'y ajoute : sans elle, le dernier réglage passait sous la barre.
  static const _hauteurBarre = 74.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Les APK deja installes ne servent plus a rien et pesent une centaine de
    // mega-octets chacun. Le lancement est le seul moment ou on le sait avec
    // certitude : l'application tourne, donc sa version a bien ete installee.
    unawaited(UpdateService.instance.purgerAnciens());
    _verifierMiseAJour();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Au retour dans l'application, pas sur une alarme : une mise à jour ne
    // sert qu'au moment où l'on ouvre Rempart. Le service se charge lui-même
    // de n'interroger le serveur qu'une fois toutes les six heures.
    if (state == AppLifecycleState.resumed) _verifierMiseAJour();
  }

  Future<void> _verifierMiseAJour() async {
    final version = await UpdateService.instance.chercherSiEcheance();
    if (version == null || !mounted) return;
    final decline = await proposerMiseAJour(context, version);
    // La fenêtre ne se referme que sur un refus explicite. Passé le
    // « Installer », l'issue échappe à l'application : si l'installation n'a
    // pas abouti, la mise à jour doit revenir à la prochaine ouverture, pas
    // dans six heures.
    if (decline) await UpdateService.instance.reporterVerification();
  }

  @override
  Widget build(BuildContext context) {
    final reserve = _hauteurBarre + MediaQuery.paddingOf(context).bottom;

    // Sur un écran large, pas de barre d'onglets : elle s'étirait sur toute
    // la largeur pour deux entrées, et « Paramètres » a rejoint le menu du
    // panneau de gauche, où l'on va déjà chercher le reste. La barre reste
    // sur un téléphone, où elle est le geste attendu.
    if (MediaQuery.sizeOf(context).width >= _seuilDeuxColonnes) {
      return const Scaffold(body: _Messages());
    }

    return Scaffold(
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: reserve),
            child: IndexedStack(
              index: _onglet,
              children: const [
                _Messages(),
                SettingsScreen(),
              ],
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _BarreOnglets(
              actif: _onglet,
              onChange: (index) => setState(() => _onglet = index),
            ),
          ),
        ],
      ),
    );
  }
}

/// Barre d'onglets en capsule flottante, dans la même famille que l'en-tête
/// des conversations et la barre de saisie.
class _BarreOnglets extends StatelessWidget {
  const _BarreOnglets({required this.actif, required this.onChange});

  final int actif;
  final ValueChanged<int> onChange;

  /// Icônes du système de l'appareil : Material sur Android et dans le
  /// navigateur, SF Symbols (via `CupertinoIcons`) sur iPhone, où des icônes
  /// Material trahissent l'application portée d'ailleurs.
  static List<(IconData, IconData, String)> get _onglets => estIOS
      ? const [
          (
            CupertinoIcons.chat_bubble_2,
            CupertinoIcons.chat_bubble_2_fill,
            'Messages',
          ),
          (CupertinoIcons.gear, CupertinoIcons.gear_solid, 'Paramètres'),
        ]
      : const [
          (Icons.forum_outlined, Icons.forum, 'Messages'),
          (Icons.settings_outlined, Icons.settings, 'Paramètres'),
        ];

  /// Largeur au-delà de laquelle la capsule cesse de s'étirer.
  ///
  /// Entre 600 et 900 points (iPad en portrait, tablette Android), l'accueil
  /// garde la disposition d'un téléphone, et la capsule traversait alors
  /// tout l'écran pour deux entrées. Un téléphone, plus étroit, n'y voit
  /// aucune différence.
  static const _largeurMax = 480.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          RempartTokens.espaceL,
          0,
          RempartTokens.espaceL,
          RempartTokens.espaceS,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _largeurMax),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.78 : 0.86,
                  ),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color:
                        theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
                  ),
                  boxShadow: RempartTokens.ombreDouce(theme.brightness),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: RempartTokens.espaceS,
                    vertical: RempartTokens.espaceS,
                  ),
                  child: Row(
                    children: [
                      for (var i = 0; i < _onglets.length; i++)
                        Expanded(
                          child: _Onglet(
                            icone: actif == i ? _onglets[i].$2 : _onglets[i].$1,
                            libelle: _onglets[i].$3,
                            actif: actif == i,
                            onTap: () => onChange(i),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Onglet extends StatelessWidget {
  const _Onglet({
    required this.icone,
    required this.libelle,
    required this.actif,
    required this.onTap,
  });

  final IconData icone;
  final String libelle;
  final bool actif;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final couleur =
        actif ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant;

    // `selected` : la couleur et la pastille disaient à l'oeil quel onglet est
    // ouvert, rien ne le disait à l'oreille.
    return Semantics(
      selected: actif,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: dureeAnimation(context, const Duration(milliseconds: 180)),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            // Pastille teintée sous l'onglet courant : la couleur seule se
            // remarque mal du coin de l'œil.
            color: actif
                ? theme.colorScheme.primary.withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icone, size: 22, color: couleur),
              const SizedBox(height: 2),
              Text(
                libelle,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: couleur,
                  fontWeight: actif ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// L'onglet Messages : la liste seule, ou la liste et la conversation côte à
/// côte quand l'écran est assez large.
///
/// Sur un téléphone, toucher une conversation empile un écran par-dessus,
/// comme toujours. Sur un écran large, elle s'ouvre **à côté** : c'est ce que
/// font Telegram et les autres clients de bureau, et cela évite de perdre la
/// liste à chaque message lu.
class _Messages extends ConsumerWidget {
  const _Messages();

  /// Largeur de la liste, fixe : elle n'a rien à gagner à s'étirer, et une
  /// colonne de largeur constante d'un écran à l'autre se parcourt mieux.
  static const _largeurListe = 360.0;

  /// Arrondi du panneau flottant, dans la famille du reste (capsules,
  /// bulles) sans aller jusqu'à la pilule : une fenêtre reste une fenêtre.
  static const _rayonPanneau = 20.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, contraintes) {
        if (contraintes.maxWidth < _seuilDeuxColonnes) {
          return const ConversationsScreen();
        }

        final roomId = ref.watch(selectedRoomIdProvider);
        final theme = Theme.of(context);
        return Row(
          children: [
            // Une fenêtre posée sur le fond, pas une colonne collée au bord :
            // les coins arrondis et l'ombre disent que la liste et la
            // conversation sont deux plans distincts, là où un simple filet
            // vertical donnait une page coupée en deux.
            // La même marge sur les quatre côtés : sans celle de droite, la
            // fenêtre venait toucher la conversation, et une fenêtre posée
            // contre sa voisine ne se lit plus comme posée.
            Padding(
              padding: const EdgeInsets.all(RempartTokens.espaceM),
              child: SizedBox(
                width: _largeurListe,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_rayonPanneau),
                    boxShadow: RempartTokens.ombreDouce(theme.brightness),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(_rayonPanneau),
                    child: const ConversationsScreen(deuxColonnes: true),
                  ),
                ),
              ),
            ),
            Expanded(
              child: roomId == null
                  ? const _AucuneConversation()
                  : ChatScreen(
                      // La clé force la reconstruction au changement de
                      // conversation : sans elle, l'écran garderait l'état de
                      // la précédente, timeline et saisie comprises.
                      key: ValueKey(roomId),
                      conversationId: roomId,
                      enPanneau: true,
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// Ce qu'on montre à droite tant qu'aucune conversation n'est choisie.
class _AucuneConversation extends StatelessWidget {
  const _AucuneConversation();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.forum_outlined,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Choisissez une conversation',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
