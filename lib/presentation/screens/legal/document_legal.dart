import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../widgets/adaptive/adaptive.dart';

/// Une section d'un document légal : un titre, puis des paragraphes.
///
/// Le contenu est du texte, pas du markdown : ces documents n'ont besoin ni de
/// gras ni de liens, et une puce se rend très bien avec un « - » en tête de
/// paragraphe. Autant éviter un moteur de rendu de plus.
@immutable
class SectionLegale {
  const SectionLegale(this.titre, this.paragraphes);

  final String titre;
  final List<String> paragraphes;
}

/// Écran de lecture d'un document légal.
///
/// Partagé par les conditions d'utilisation et la politique de
/// confidentialité : même mise en page, seul le contenu change.
class DocumentLegal extends StatelessWidget {
  const DocumentLegal({
    required this.titre,
    required this.miseAJour,
    required this.sections,
    super.key,
  });

  final String titre;

  /// Date de dernière mise à jour, affichée en tête : un document légal sans
  /// date ne dit pas quelle version l'utilisateur a sous les yeux.
  final String miseAJour;

  final List<SectionLegale> sections;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AdaptiveScaffold(
      title: titre,
      previousPageTitle: 'Paramètres',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          RempartTokens.espaceL,
          RempartTokens.espaceL,
          RempartTokens.espaceL,
          RempartTokens.espaceXl * 2,
        ),
        children: [
          Text(
            'Dernière mise à jour : $miseAJour',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: RempartTokens.espaceL),
          for (final section in sections) ...[
            const SizedBox(height: RempartTokens.espaceL),
            Text(section.titre, style: theme.textTheme.titleMedium),
            const SizedBox(height: RempartTokens.espaceS),
            for (final paragraphe in section.paragraphes) ...[
              Text(paragraphe, style: theme.textTheme.bodyMedium),
              const SizedBox(height: RempartTokens.espaceS),
            ],
          ],
        ],
      ),
    );
  }
}
