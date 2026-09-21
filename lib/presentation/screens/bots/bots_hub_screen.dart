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
  const BotsHubScreen({super.key});

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
          AdaptiveListTile(
            leading: const CircleAvatar(child: Icon(Icons.storefront)),
            title: const Text('Boutique à agents'),
            subtitle: const Text('Faire développer un agent sur mesure'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/boutique-agents'),
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
