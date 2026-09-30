import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../data/services/statut_presence.dart';
import '../adaptive/adaptive.dart';

/// « Mon statut » : ce que les autres voient de ma présence.
class StatutTile extends StatelessWidget {
  const StatutTile({super.key});

  Future<void> _choisir(BuildContext context) async {
    final actuel = StatutPresence.instance.choix.value;
    final choix = await feuilleAdaptative<StatutChoisi>(
      context: context,
      // Les widgets Material ont besoin d'un Material ancêtre dans un contexte
      // Cupertino, où la feuille n'en fournit pas.
      builder: (context) => Material(
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Mon statut',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final statut in StatutChoisi.values)
                ListTile(
                  leading: _Pastille(statut),
                  title: Text(statut.libelle),
                  subtitle: Text(statut.description),
                  trailing: statut == actuel ? const Icon(Icons.check) : null,
                  selected: statut == actuel,
                  onTap: () => Navigator.pop(context, statut),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (choix != null) await StatutPresence.instance.choisir(choix);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<StatutChoisi>(
      valueListenable: StatutPresence.instance.choix,
      builder: (context, statut, _) => ListTile(
        leading: _Pastille(statut),
        title: const Text('Mon statut'),
        subtitle: Text('${statut.libelle} · ${statut.description}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _choisir(context),
      ),
    );
  }
}

/// La pastille que les autres voient : verte en ligne, orange absent, grise
/// invisible (comme hors ligne).
class _Pastille extends StatelessWidget {
  const _Pastille(this.statut);

  final StatutChoisi statut;

  @override
  Widget build(BuildContext context) {
    final couleur = switch (statut) {
      StatutChoisi.automatique => RempartTokens.succes,
      StatutChoisi.absent => RempartTokens.alerte,
      StatutChoisi.invisible => Colors.grey,
    };
    return SizedBox(
      width: 24,
      child: Center(
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: couleur, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
