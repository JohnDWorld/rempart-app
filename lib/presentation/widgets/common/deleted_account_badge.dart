import 'package:flutter/material.dart';

/// Pastille signalant que le compte du correspondant n'existe plus.
///
/// La room et son historique restent accessibles, mais l'autre utilisateur a
/// supprimé son compte : plus aucun message n'y arrivera.
///
/// Détection : le mxid du contact dérive bien d'un id Supabase
/// (`u_<uuid sans tirets>`) mais le profil Supabase correspondant a disparu.
/// Voir `RoomContact.deleted`.
class DeletedAccountBadge extends StatelessWidget {
  const DeletedAccountBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Compte supprimé',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onErrorContainer,
              fontWeight: FontWeight.w500,
            ),
      ),
    );
  }
}
