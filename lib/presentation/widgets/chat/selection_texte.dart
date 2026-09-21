import 'package:flutter/material.dart';

import '../../../app/theme.dart';

/// Ouvre le message dans une feuille où le texte se sélectionne au doigt.
///
/// Pourquoi une feuille plutôt qu'une sélection directe dans la bulle : dans
/// le fil, l'appui long est déjà pris, c'est lui qui ouvre les réactions et le
/// menu. Rendre les bulles sélectionnables (`SelectionArea`) mettrait les deux
/// gestes en concurrence sur le même doigt, et l'un des deux perdrait selon la
/// profondeur du widget touché, ce qui est la pire des réponses : un geste qui
/// marche une fois sur deux. Telegram fait le même choix, avec la même entrée
/// de menu.
///
/// « Copier » reste à côté et copie tout : c'est le geste courant, et il ne
/// doit pas coûter une étape de plus.
Future<void> ouvrirSelectionTexte(BuildContext context, String texte) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: ConstrainedBox(
          // La feuille ne dépasse pas les trois quarts de l'écran : au-delà
          // elle cache le fil sans rien montrer de plus, le texte défilant
          // déjà.
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.75,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              RempartTokens.espaceL,
              0,
              RempartTokens.espaceL,
              RempartTokens.espaceL,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sélectionner le texte',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: RempartTokens.espaceXs),
                Text(
                  'Appui long sur un mot, puis ajustez les poignées.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: RempartTokens.espaceM),
                Flexible(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      texte,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
