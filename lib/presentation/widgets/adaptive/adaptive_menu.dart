import 'package:flutter/material.dart';

import '../../../core/plateforme.dart';
import 'adaptive_dialog.dart';

/// Entrée d'un [MenuAdaptatif].
class EntreeMenu<T> {
  const EntreeMenu({
    required this.valeur,
    required this.libelle,
    this.icone,
    this.destructive = false,
  });

  final T valeur;
  final String libelle;

  /// Sans icône, l'entrée Material est un simple texte, comme dans les menus
  /// qui n'en avaient pas.
  final IconData? icone;

  /// Supprime ou coupe quelque chose sans retour : en rouge sur iOS. Sans
  /// effet sur Android, dont les menus n'en distinguaient aucune.
  final bool destructive;
}

/// Bouton qui ouvre un menu d'actions, au geste de chaque plateforme : une
/// feuille d'actions qui monte du bas sur iPhone, un menu déroulant ailleurs.
///
/// Une seule liste d'entrées sert aux deux. Écrire le menu deux fois, une par
/// plateforme, est précisément ce qui fait diverger les deux versions d'une
/// même application au fil des ajouts.
class MenuAdaptatif<T> extends StatelessWidget {
  const MenuAdaptatif({
    required this.entrees,
    required this.onSelected,
    this.enabled = true,
    this.tooltip = 'Actions',
    this.icone,
    super.key,
  });

  final List<EntreeMenu<T>> entrees;
  final ValueChanged<T> onSelected;
  final bool enabled;
  final String tooltip;

  /// Par défaut, les trois points de la plateforme (horizontaux sur iOS).
  final Widget? icone;

  @override
  Widget build(BuildContext context) {
    final bouton = icone ?? Icon(Icons.adaptive.more);

    if (estIOS) {
      return IconButton(
        icon: bouton,
        tooltip: tooltip,
        onPressed: enabled ? () => _ouvrirFeuille(context) : null,
      );
    }

    return PopupMenuButton<T>(
      enabled: enabled,
      icon: bouton,
      tooltip: tooltip,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final entree in entrees)
          PopupMenuItem<T>(
            value: entree.valeur,
            child: entree.icone == null
                ? Text(entree.libelle)
                : ListTile(
                    leading: Icon(entree.icone),
                    title: Text(entree.libelle),
                    contentPadding: EdgeInsets.zero,
                  ),
          ),
      ],
    );
  }

  Future<void> _ouvrirFeuille(BuildContext context) async {
    final choix = await showAdaptiveActionSheet<T>(
      context: context,
      actions: [
        for (final entree in entrees)
          AdaptiveAction<T>(
            label: entree.libelle,
            value: entree.valeur,
            isDestructive: entree.destructive,
          ),
      ],
      cancelAction: AdaptiveAction<T>(label: 'Annuler'),
    );
    if (choix != null) onSelected(choix);
  }
}
