import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/plateforme.dart';
import '../../../data/providers/taille_texte.dart';
import '../adaptive/adaptive.dart';

/// Réglage de la taille du texte des messages.
///
/// Le réglage du système agrandit toute l'interface et ne se règle pas par
/// conversation ; celui-ci ne touche que les messages, ce qui permet de lire
/// confortablement sans déformer le reste de l'application. Les deux se
/// cumulent.
class TailleTexteTile extends ConsumerWidget {
  const TailleTexteTile({super.key});

  Future<void> _choisir(BuildContext context, WidgetRef ref) async {
    final choix = await feuilleAdaptative<TailleTexte>(
      context: context,
      // Les widgets Material ont besoin d'un Material ancêtre dans un contexte
      // Cupertino, où la feuille n'en fournit pas.
      builder: (context) => Material(
        color: Theme.of(context).colorScheme.surface,
        child: _Feuille(actuelle: ref.read(tailleTexteProvider)),
      ),
    );
    if (choix == null) return;
    ref.read(tailleTexteProvider.notifier).state = choix;
    await enregistrerTailleTexte(choix);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taille = ref.watch(tailleTexteProvider);
    return ListTile(
      leading: Icon(estIOS ? Icons.text_fields : Icons.format_size),
      title: const Text('Taille du texte'),
      subtitle: Text('${taille.libelle} · messages uniquement'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _choisir(context, ref),
    );
  }
}

/// Le choix, avec un aperçu qui change en même temps que lui.
///
/// L'aperçu n'est pas un ornement : sans lui, il faut valider, sortir, ouvrir
/// une conversation, revenir. Autant de va-et-vient qu'il y a de tailles.
class _Feuille extends StatefulWidget {
  const _Feuille({required this.actuelle});

  final TailleTexte actuelle;

  @override
  State<_Feuille> createState() => _FeuilleState();
}

class _FeuilleState extends State<_Feuille> {
  late var _choix = widget.actuelle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyLarge!;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Taille du texte', style: theme.textTheme.titleMedium),
          ),
          // Une vraie bulle plutôt qu'une ligne de texte : c'est la largeur
          // disponible qui fait qu'une taille passe ou non.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.78,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'Voilà à quoi ressembleront tes messages.',
                  style: base.copyWith(
                    fontSize: (base.fontSize ?? 15.5) * _choix.facteur,
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
              ),
            ),
          ),
          RadioGroup<TailleTexte>(
            groupValue: _choix,
            onChanged: (v) => setState(() => _choix = v!),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final taille in TailleTexte.values)
                  RadioListTile<TailleTexte>(
                    value: taille,
                    title: Text(taille.libelle),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: FilledButton(
              onPressed: () => Navigator.pop(context, _choix),
              child: const Text('Appliquer'),
            ),
          ),
        ],
      ),
    );
  }
}
