import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../data/providers/providers.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/common/user_avatar.dart';

/// Personnes bloquées, et de quoi les débloquer.
///
/// Bloquer se fait depuis une conversation, en un geste ; débloquer demande de
/// retrouver quelqu'un dont, justement, on ne voit plus rien. D'où cet écran :
/// sans lui, un blocage serait sans retour.
class UtilisateursBloquesScreen extends ConsumerWidget {
  const UtilisateursBloquesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // La liste vit dans les données de compte Matrix : elle change au gré des
    // syncs, d'où la dépendance au compteur d'état.
    ref.watch(matrixStateNotifierProvider);
    final theme = Theme.of(context);
    final service = ref.read(matrixServiceProvider);
    final bloques = service.utilisateursBloques;

    return AdaptiveScaffold(
      title: 'Personnes bloquées',
      previousPageTitle: 'Paramètres',
      body: bloques.isEmpty
          ? _Vide()
          : ListView(
              padding: const EdgeInsets.only(bottom: RempartTokens.espaceXl),
              children: [
                Padding(
                  padding: const EdgeInsets.all(RempartTokens.espaceL),
                  child: Text(
                    'Vous ne recevez plus les messages de ces personnes. Les '
                    'débloquer ne restaure pas ce qui a été envoyé entre-temps.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                for (final mxid in bloques)
                  _LigneBloque(
                    mxid: mxid,
                    onDebloquer: () => _debloquer(context, ref, mxid),
                  ),
              ],
            ),
    );
  }

  Future<void> _debloquer(
    BuildContext context,
    WidgetRef ref,
    String mxid,
  ) async {
    final confirme = await showAdaptiveAlert<bool>(
      context: context,
      title: 'Débloquer ${ref.read(nomContactProvider(mxid)) ?? 'ce contact'}',
      content: 'Cette personne pourra de nouveau vous écrire.',
      cancelText: 'Annuler',
      confirmText: 'Débloquer',
    );
    if (confirme != true || !context.mounted) return;

    try {
      await ref.read(matrixServiceProvider).debloquerUtilisateur(mxid);
      ref.read(matrixStateNotifierProvider.notifier).state++;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${ref.read(nomContactProvider(mxid)) ?? 'Ce contact'} a été débloqué',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Déblocage impossible : $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }
}

/// Une personne bloquée, avec son vrai nom.
///
/// Le mxid n'apparaît qu'en dernier recours, quand aucun nom ne se résout :
/// dans une LISTE, plusieurs lignes identiques ne se débloqueraient plus, il
/// faut donc bien distinguer les entrées par quelque chose. Partout ailleurs
/// (titres, phrases, confirmations) l'identifiant ne sort jamais.
class _LigneBloque extends ConsumerWidget {
  const _LigneBloque({required this.mxid, required this.onDebloquer});

  final String mxid;
  final VoidCallback onDebloquer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nom = ref.watch(nomContactProvider(mxid));
    return ListTile(
      leading: UserAvatar(name: nom ?? '?', size: 40),
      title: Text(nom ?? 'Contact inconnu'),
      trailing: TextButton(
        onPressed: onDebloquer,
        child: const Text('Débloquer'),
      ),
    );
  }
}

class _Vide extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RempartTokens.espaceXl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.block,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: RempartTokens.espaceL),
            Text('Personne de bloqué', style: theme.textTheme.titleMedium),
            const SizedBox(height: RempartTokens.espaceS),
            Text(
              "Vous pouvez bloquer quelqu'un depuis un de ses messages, en "
              'appuyant longuement dessus.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
