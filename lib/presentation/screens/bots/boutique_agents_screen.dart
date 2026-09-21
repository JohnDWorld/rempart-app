import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../data/providers/providers.dart';
import '../../widgets/adaptive/adaptive.dart';

/// Vitrine de la boutique à agents : faire développer un agent sur mesure.
///
/// « Mes bots » s'adresse à qui sait déjà écrire un agent et n'a besoin que
/// d'un token. Cet écran s'adresse à tous les autres : la commande se passe
/// sur le site, et la livraison arrive dans l'app sans rien à installer.
///
/// Le seul élément que l'utilisateur doit fournir est son identifiant Rempart,
/// affiché ici et copiable : c'est la clé sur laquelle la gateway rattache le
/// bot livré, donc la seule chose qui le fera apparaître dans SES bots.
class BoutiqueAgentsScreen extends ConsumerWidget {
  const BoutiqueAgentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final identifiant = ref.watch(currentUserIdProvider);

    return AdaptiveScaffold(
      title: 'Boutique à agents',
      previousPageTitle: 'Bots',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: theme.colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.auto_awesome,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Un agent sur mesure, livré dans Rempart',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Décrivez ce que vous voulez automatiser : veille, '
                    'relances, résumés, suivi de commandes. Nous construisons '
                    "l'agent et l'hébergeons. Vous n'avez rien à installer, "
                    'ni serveur à faire tourner.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Comment ça se passe', style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),
          const _Etape(
            numero: 1,
            titre: 'Vous décrivez le besoin',
            detail: 'Sur le site, en quelques lignes. Nous répondons avec un '
                'devis et le détail de ce que fera votre agent.',
          ),
          const _Etape(
            numero: 2,
            titre: 'Vous donnez votre identifiant Rempart',
            detail: 'Le bouton ci-dessous le copie. Il nous sert à rattacher '
                "l'agent à votre compte, et à rien d'autre.",
          ),
          const _Etape(
            numero: 3,
            titre: "L'agent apparaît dans vos bots",
            detail: 'Vous le retrouvez dans « Mes bots » et lui parlez comme à '
                "n'importe quel contact.",
            dernier: true,
          ),
          const SizedBox(height: 24),
          _CarteIdentifiant(identifiant: identifiant),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _ouvrirBoutique(context),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Commander sur le site'),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: () => _ecrire(context),
              icon: const Icon(Icons.mail_outline, size: 18),
              label: const Text('Une question ? Nous écrire'),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              AppConstants.boutiqueAgentsEmail,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Les conversations avec un agent ne sont pas chiffrées : comme tout '
            'bot, il lit vos messages pour y répondre. Vos conversations avec '
            'vos contacts, elles, restent chiffrées de bout en bout.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  /// Ouvre l'application e-mail sur l'adresse de la boutique.
  ///
  /// Le sujet est prérempli : une question de commande arrive ainsi triée,
  /// sans que la personne ait à expliquer d'où elle vient.
  Future<void> _ecrire(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.parse(
      'mailto:${AppConstants.boutiqueAgentsEmail}'
      '?subject=${Uri.encodeComponent('Question sur un agent sur mesure')}',
    );
    try {
      final ouvert = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ouvert) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Aucune application e-mail trouvée.')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text("Impossible d'ouvrir la messagerie : $e")),
      );
    }
  }

  Future<void> _ouvrirBoutique(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.parse(AppConstants.boutiqueAgentsUrl);
    try {
      final ouvert = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ouvert) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Aucun navigateur trouvé.')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text("Impossible d'ouvrir la boutique : $e")),
      );
    }
  }
}

/// Une étape de la marche à suivre, numérotée et reliée à la suivante.
class _Etape extends StatelessWidget {
  const _Etape({
    required this.numero,
    required this.titre,
    required this.detail,
    this.dernier = false,
  });

  final int numero;
  final String titre;
  final String detail;
  final bool dernier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: theme.colorScheme.secondaryContainer,
              child: Text(
                '$numero',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
            if (!dernier)
              Container(
                width: 2,
                height: 40,
                color: theme.colorScheme.outlineVariant,
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: dernier ? 0 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titre, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// L'identifiant Rempart de l'utilisateur, à copier et transmettre.
class _CarteIdentifiant extends StatelessWidget {
  const _CarteIdentifiant({required this.identifiant});

  final String? identifiant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Votre identifiant Rempart', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Copiez-le et collez-le dans votre commande. Il ne donne accès '
              'à rien : il désigne votre compte, comme un numéro de client.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            if (identifiant == null)
              Text(
                'Identifiant indisponible : reconnectez-vous.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              )
            else
              // Copié, jamais affiché : une suite de trente-six caractères ne
              // se lit ni ne se recopie à la main, et l'écrire n'apprend rien
              // à personne. Le bouton fait tout le travail.
              OutlinedButton.icon(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await Clipboard.setData(ClipboardData(text: identifiant!));
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Identifiant copié.')),
                  );
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copier mon identifiant'),
              ),
          ],
        ),
      ),
    );
  }
}
