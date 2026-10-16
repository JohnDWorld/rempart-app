import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/profile.dart';
import '../../../data/providers/providers.dart';
import '../adaptive/adaptive.dart';
import 'user_avatar.dart';

/// Montre qui porte le nom d'utilisateur [nom], et propose de lui écrire.
///
/// Le chemin des codes QR et des liens de contact : rien n'est tapé, et la
/// fiche (photo, nom, `@nom`) laisse vérifier qu'on a la bonne personne avant
/// d'ouvrir la conversation. Avec [remplacer], l'écran d'où l'on vient
/// (« Nouveau message ») cède sa place, comme après une recherche.
Future<void> proposerContact(
  BuildContext context,
  String nom, {
  bool remplacer = false,
}) async {
  // Pris avant toute attente : l'écran appelant peut disparaître entre-temps.
  final conteneur = ProviderScope.containerOf(context, listen: false);
  final routeur = GoRouter.of(context);
  final navigateur = Navigator.of(context, rootNavigator: true);

  final Profile? trouve;
  try {
    trouve =
        await conteneur.read(profileServiceProvider).getProfileByUsername(nom);
  } catch (e) {
    debugPrint('Contact : recherche impossible ($e)');
    if (context.mounted) {
      await _avertir(
        context,
        'Recherche impossible',
        'Vérifiez la connexion, puis réessayez.',
      );
    }
    return;
  }
  if (!context.mounted) return;
  if (trouve == null) {
    await _avertir(
      context,
      'Personne à ce nom',
      'Aucun compte Rempart ne porte le nom @$nom.',
    );
    return;
  }
  final profil = trouve;
  if (profil.id == conteneur.read(currentUserIdProvider)) {
    await _avertir(context, "C'est vous", 'Ce code est le vôtre.');
    return;
  }

  final ecrire = await showAdaptiveDialog<bool>(
    context: context,
    builder: (context) => DialogueAdaptatif(
      title: Text(profil.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          UserAvatar(name: profil.name, imageUrl: profil.avatarUrl, size: 72),
          const SizedBox(height: 12),
          Text('@${profil.username}'),
        ],
      ),
      actions: [
        ActionDialogue(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        ActionDialogue(
          principale: true,
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Écrire'),
        ),
      ],
    ),
  );
  if (!(ecrire ?? false) || !context.mounted) return;

  // La création d'un tête-à-tête prend une à deux secondes : sans attente
  // visible, on toucherait de nouveau « Écrire ».
  unawaited(
    showAdaptiveDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator.adaptive()),
    ),
  );
  try {
    final matrix = conteneur.read(matrixServiceProvider);
    final roomId = await matrix
        .createDirectChat(matrix.matrixUserIdForSupabaseId(profil.id));
    navigateur.pop();
    unawaited(
      remplacer
          ? routeur.pushReplacement('/chat/$roomId')
          : routeur.push('/chat/$roomId'),
    );
  } catch (e) {
    navigateur.pop();
    if (context.mounted) {
      await _avertir(context, 'Conversation impossible', '$e');
    }
  }
}

Future<void> _avertir(BuildContext context, String titre, String texte) {
  return showAdaptiveDialog<void>(
    context: context,
    builder: (context) => DialogueAdaptatif(
      title: Text(titre),
      content: Text(texte),
      actions: [
        ActionDialogue(
          principale: true,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
