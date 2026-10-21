import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../widgets/adaptive/adaptive.dart';

/// Choix entre ses propres bots et ceux fournis par Rempart.
///
/// Les deux n'ont rien à voir : « Mes bots » sert à créer et configurer des
/// comptes que l'on pilote soi-même, « Bots système » à démarrer une
/// conversation avec l'assistant livré avec l'app. Les mêler sur un seul écran
/// noyait la création de bot derrière un catalogue.
class BotsHubScreen extends StatelessWidget {
  const BotsHubScreen({super.key, this.decouverte = false});

  /// Fin de la présentation (`PresentationScreen`) : on dit où l'on est, et
  /// la Boutique à agents est mise en avant. On n'arrive ici que par
  /// « Nouveau message › Parler à un bot », que presque personne ne trouve
  /// seul.
  final bool decouverte;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AdaptiveScaffold(
      title: 'Bots',
      previousPageTitle: 'Retour',
      actions: [
        IconButton(
          icon: const Icon(Icons.explore_outlined),
          tooltip: 'Découvrir des bots',
          onPressed: () => context.push('/bot-directory'),
        ),
      ],
      body: ListView(
        children: [
          if (decouverte)
            Card(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Vos bots et vos agents sont ici. Vous retrouverez ce menu '
                  'à tout moment depuis Nouveau message › Parler à un bot.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Les conversations avec un bot ne sont pas chiffrées : '
              'le bot lit vos messages pour y répondre.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          AdaptiveListTile(
            leading: const CircleAvatar(child: Icon(Icons.smart_toy_outlined)),
            title: const Text('Mes bots'),
            subtitle: const Text('Créer et configurer vos propres bots'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/my-bots'),
          ),
          _MiseEnAvant(
            active: decouverte,
            child: AdaptiveListTile(
              leading: const CircleAvatar(child: Icon(Icons.storefront)),
              title: const Text('Boutique à agents'),
              subtitle: const Text('Faire développer un agent sur mesure'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/boutique-agents'),
            ),
          ),
          AdaptiveListTile(
            leading: const CircleAvatar(child: Icon(Icons.support_agent)),
            title: const Text('Bots système'),
            subtitle: const Text('Assistant IA et bot de démonstration'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/bots/system'),
          ),
        ],
      ),
    );
  }
}

/// Un liseré de la couleur d'accent autour de [child] quand [active].
class _MiseEnAvant extends StatelessWidget {
  const _MiseEnAvant({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!active) return child;
    final couleurs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: couleurs.primary, width: 2),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
