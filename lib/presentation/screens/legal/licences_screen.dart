import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/settings/mise_a_jour.dart';

/// Écran « Code source et licences ».
///
/// Il n'est pas là par transparence militante : le protocole Matrix et le
/// chiffrement viennent de bibliothèques sous AGPL, l'application est donc une
/// œuvre combinée, et la licence **exige** que celui qui reçoit le binaire
/// puisse obtenir la source correspondante. Cet écran est la façon la plus
/// simple de tenir cette obligation, et il se trouve qu'elle sert aussi le
/// propos : une messagerie qui se réclame de la souveraineté gagne à être
/// lisible par ceux qui lui confient leurs conversations.
///
/// « Correspondante » est le mot qui compte : le dépôt public reçoit un
/// instantané étiqueté à chaque version distribuée, d'où la version affichée
/// ici, qui dit quelle étiquette regarder.
class LicencesScreen extends StatelessWidget {
  const LicencesScreen({super.key});

  Future<void> _ouvrirDepot(BuildContext context) async {
    var ouvert = false;
    try {
      ouvert = await launchUrl(
        Uri.parse(AppConstants.codeSourceUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      ouvert = false;
    }
    if (ouvert || !context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text("Impossible d'ouvrir le dépôt.")),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AdaptiveScaffold(
      title: 'Code source et licences',
      previousPageTitle: 'Paramètres',
      body: ListView(
        padding: const EdgeInsets.all(RempartTokens.espaceL),
        children: [
          Text('Rempart est un logiciel libre',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: RempartTokens.espaceM),
          Text(
            "Le code de l'application est publié sous licence AGPL-3.0-or-later. "
            'Chacun peut le lire, le modifier et le redistribuer, à condition '
            'de laisser les mêmes droits à ceux qui recevront sa version.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: RempartTokens.espaceM),
          Text(
            "Ce n'est pas une faveur : Rempart s'appuie sur le SDK Matrix et "
            'sur vodozemac, eux-mêmes sous cette licence, et elle se transmet '
            'à ce qui les utilise.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: RempartTokens.espaceS),
          Text(
            'Le nom « Rempart » et le logo restent des marques : une version '
            'modifiée doit porter un autre nom, pour que personne ne se '
            'trompe sur qui reçoit ses conversations.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: RempartTokens.espaceXl),
          _Entree(
            icone: Icons.code,
            titre: 'Voir le code source',
            sousTitre: AppConstants.codeSourceUrl
                .replaceFirst(RegExp('^https://'), ''),
            onTap: () => _ouvrirDepot(context),
          ),
          FutureBuilder<String>(
            future: versionInstallee(),
            builder: (context, instantane) {
              final version = instantane.data;
              if (version == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: RempartTokens.espaceS),
                child: Text(
                  "La version installée correspond à l'étiquette "
                  'v$version du dépôt.',
                  style: theme.textTheme.bodySmall,
                ),
              );
            },
          ),
          const SizedBox(height: RempartTokens.espaceL),
          _Entree(
            icone: Icons.article_outlined,
            titre: 'Licences des composants',
            sousTitre: 'Les bibliothèques utilisées et leurs auteurs',
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'Rempart Messenger',
              applicationLegalese: '© 2026 John Demory\n'
                  'Sous licence AGPL-3.0-or-later',
            ),
          ),
        ],
      ),
    );
  }
}

/// Une ligne cliquable, dessinée à la main plutôt qu'en `ListTile` : l'écran
/// est monté aussi bien sous Cupertino que sous Material, et un `ListTile` y
/// exigerait un `Material` parent.
class _Entree extends StatelessWidget {
  const _Entree({
    required this.icone,
    required this.titre,
    required this.sousTitre,
    required this.onTap,
  });

  final IconData icone;
  final String titre;
  final String sousTitre;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // `Material` transparent obligatoire : l'écran s'ouvre aussi sous
    // Cupertino, où rien n'en fournit, et `InkWell` y échoue au montage avec
    // « No Material widget found ».
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RempartTokens.rayonCarte),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: RempartTokens.espaceM,
            horizontal: RempartTokens.espaceS,
          ),
          child: Row(
            children: [
              Icon(icone, size: 22, color: theme.colorScheme.primary),
              const SizedBox(width: RempartTokens.espaceL),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titre, style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 2),
                    Text(sousTitre, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              Icon(
                Icons.adaptive.arrow_forward,
                size: 18,
                color: theme.textTheme.bodySmall?.color,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
