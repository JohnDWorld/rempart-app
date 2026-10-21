import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/mouvement.dart';
import '../../data/services/presentation.dart';
import '../widgets/adaptive/adaptive.dart';

/// La présentation de Rempart, à la première ouverture d'un compte.
///
/// Trois écrans, puis le vrai menu Bots, où la Boutique à agents est mise en
/// avant (`/bots?decouverte=1`). C'est le but autant que la présentation :
/// on n'arrive à ce menu que par « Nouveau message › Parler à un bot », et
/// presque personne ne l'aurait trouvé seul. « Passer » y mène aussi.
class PresentationScreen extends StatefulWidget {
  const PresentationScreen({super.key, this.surFin});

  /// Remplace la suite (le menu Bots), pour les tests.
  final VoidCallback? surFin;

  @override
  State<PresentationScreen> createState() => _PresentationScreenState();
}

class _PresentationScreenState extends State<PresentationScreen> {
  final _pages = PageController();
  int _page = 0;

  // `\u00a0` : l'espace insécable de la typographie française, sans laquelle
  // la ligne pouvait commencer par les deux-points (vu sur l'émulateur).
  static const _ecrans = [
    _Ecran(
      titre: 'Bienvenue sur Rempart',
      texte: 'Vos conversations sont chiffrées de bout en bout\u00a0: seuls vos '
          'correspondants peuvent les lire. Rempart est hébergé en France.',
    ),
    _Ecran(
      icone: Icons.alternate_email,
      titre: 'Retrouvez vos proches',
      texte: "Chacun a un nom d'utilisateur unique, comme @marie.dupont\u00a0: "
          "il évite de confondre deux homonymes. Pour écrire à quelqu'un, "
          'touchez le crayon, puis cherchez son @nom ou scannez son code QR.',
    ),
    _Ecran(
      icone: Icons.auto_awesome,
      titre: 'Des agents à votre service',
      texte: 'Un agent est un assistant qui travaille pour vous dans une '
          'conversation\u00a0: veille, rappels, résumés. Créez le vôtre, ou '
          'faites-en développer un sur mesure par la Boutique à agents.',
    ),
  ];

  bool get _dernier => _page == _ecrans.length - 1;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _suivant() => _pages.nextPage(
        duration: dureeAnimation(context, const Duration(milliseconds: 280)),
        curve: Curves.easeOutCubic,
      );

  void _terminer() {
    final surFin = widget.surFin;
    if (surFin != null) return surFin();
    unawaited(Presentation.marquerVue());
    // À la place de la présentation : le retour mène ensuite à l'écran d'où
    // elle est partie (l'accueil, ou les paramètres).
    context.pushReplacement('/bots?decouverte=1');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.all(RempartTokens.espaceS),
                // Rien à passer sur le dernier écran : son bouton mène au
                // même endroit.
                // Sa place reste (le contenu ne saute pas), pas son appui :
                // `Visibility.maintain` le laissait touchable, invisible.
                child: Visibility(
                  visible: !_dernier,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: TextButton(
                    onPressed: _terminer,
                    child: const Text('Passer'),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: _ecrans.length,
                onPageChanged: (page) => setState(() => _page = page),
                itemBuilder: (context, index) => _ecrans[index],
              ),
            ),
            Semantics(
              label: 'Écran ${_page + 1} sur ${_ecrans.length}',
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _ecrans.length; i++)
                    AnimatedContainer(
                      duration: dureeAnimation(
                        context,
                        const Duration(milliseconds: 200),
                      ),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _page ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _page
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(RempartTokens.espaceXl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: SizedBox(
                  width: double.infinity,
                  child: AdaptiveButton(
                    onPressed: _dernier ? _terminer : _suivant,
                    child: Text(_dernier ? 'Découvrir les agents' : 'Suivant'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Un écran de la présentation : une image, un titre, quelques lignes.
class _Ecran extends StatelessWidget {
  const _Ecran({required this.titre, required this.texte, this.icone});

  /// Null pour le premier écran, qui porte le logo.
  final IconData? icone;
  final String titre;
  final String texte;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final couleurs = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: RempartTokens.espaceXl),
        child: ConstrainedBox(
          // Une ligne trop longue ne se lit plus d'un trait (version web).
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 132,
                height: 132,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: couleurs.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: icone == null
                    ? SvgPicture.asset(
                        'assets/images/rempart-logo.svg',
                        width: 72,
                        height: 72,
                      )
                    : Icon(icone, size: 60, color: couleurs.onPrimaryContainer),
              ),
              const SizedBox(height: 40),
              Text(
                titre,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: RempartTokens.espaceL),
              Text(
                texte,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: couleurs.onSurfaceVariant, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
