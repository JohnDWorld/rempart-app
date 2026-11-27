import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/nom_utilisateur.dart';
import '../adaptive/adaptive.dart';

/// Points de code que la police Inter dessine elle-même, en noir et blanc.
///
/// Flutter garde alors la forme d'Inter et ignore le sélecteur d'emoji :
/// c'est le défaut du ❤️ noir (voir `pubspec.yaml`). Un emoji qui en contient
/// un (flèches, chiffres encadrés, ©, ®, ™, ‼, ⁉, ▶, ◀) n'est donc pas
/// proposé : 31 emojis sur 1625. Retoucher Inter ne convenait pas ici, les
/// chiffres et le # servent au texte. Relevé avec fontTools sur les quatre
/// graisses d'Inter, contre le jeu français du paquet : à refaire si l'une ou
/// l'autre change.
const _dessinesParInter = {
  0x23, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, //
  0xa9, 0xae, 0x203c, 0x2049, 0x2122, 0x2194, 0x2195, 0x2196, 0x2197, //
  0x2198, 0x2199, 0x21a9, 0x21aa, 0x23cf, 0x24c2, 0x25aa, 0x25b6, 0x25c0, //
  0x2b06, 0x2b1c,
};

bool dessineEnNoir(String emoji) => emoji.runes.any(_dessinesParInter.contains);

/// Le jeu français (mots-clés de la recherche), sans les emojis noirs.
List<CategoryEmoji> jeuEmojis(Locale _) => [
      for (final categorie in emojiSetFrance)
        categorie.copyWith(
          emoji: [
            for (final e in categorie.emoji)
              if (!dessineEnNoir(e.emoji))
                Emoji(e.emoji, motsCles(e.name), hasSkinTone: e.hasSkinTone),
          ],
        ),
    ];

/// La recherche du paquet ne compare que des débuts de mots-clés entiers,
/// tels qu'écrits : « bleu » ne trouvait pas 💙 (« cœur bleu »), ni « coeur »
/// la plupart des cœurs. Chaque mot-clé y gagne ses mots un à un, et leur
/// forme sans accent ni ligature, celle qu'on tape au clavier.
String motsCles(String nom) => {
      for (final cle in nom.split('|'))
        for (final forme in {
          cle.trim().toLowerCase(),
          sansAccents(cle.trim().toLowerCase())
        })
          for (final mot in [forme, ...forme.split(RegExp(r"[\s'’-]+"))])
            if (mot.isNotEmpty) mot,
    }.join(' | ');

/// Ouvre la feuille de tous les emojis et rend celui qu'on a touché, ou
/// `null` si on l'a fermée.
Future<String?> choisirEmoji(BuildContext context) => feuilleAdaptative<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => ChoixEmoji(
        onChoisi: (emoji) => Navigator.pop(context, emoji),
      ),
    );

/// Tous les emojis, comme sur WhatsApp ou Signal : récents en tête,
/// catégories, recherche en français, couleurs de peau (appui long).
class ChoixEmoji extends StatelessWidget {
  const ChoixEmoji({required this.onChoisi, super.key});

  final ValueChanged<String> onChoisi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final couleurs = theme.colorScheme;
    final fond = theme.bottomSheetTheme.backgroundColor ?? couleurs.surface;
    // Un Material pour le champ de recherche : la feuille Cupertino n'en
    // fournit pas. Il prend la forme de la feuille, sans quoi le fond des
    // onglets couvrait ses coins arrondis.
    return Material(
      color: fond,
      shape: theme.bottomSheetTheme.shape,
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          // La recherche ouvre le clavier : la feuille monte avec lui.
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: EmojiPicker(
            // Quelques emojis du jeu portent une espace à la fin.
            onEmojiSelected: (_, emoji) => onChoisi(emoji.emoji.trim()),
            config: Config(
              height: 320,
              locale: const Locale('fr'),
              emojiSet: jeuEmojis,
              emojiViewConfig: EmojiViewConfig(
                columns: 8,
                backgroundColor: fond,
                noRecents: Text(
                  'Aucun emoji récent',
                  style: TextStyle(color: couleurs.onSurfaceVariant),
                ),
              ),
              categoryViewConfig: CategoryViewConfig(
                backgroundColor: fond,
                indicatorColor: couleurs.primary,
                iconColor: couleurs.onSurfaceVariant,
                iconColorSelected: couleurs.primary,
                dividerColor: couleurs.outlineVariant,
              ),
              bottomActionBarConfig: BottomActionBarConfig(
                showBackspaceButton: false,
                backgroundColor: fond,
                buttonColor: couleurs.secondaryContainer,
                buttonIconColor: couleurs.onSecondaryContainer,
              ),
              searchViewConfig: SearchViewConfig(
                backgroundColor: fond,
                buttonIconColor: couleurs.onSurfaceVariant,
                hintText: 'Rechercher un emoji',
              ),
              skinToneConfig: SkinToneConfig(
                dialogBackgroundColor: couleurs.surfaceContainerHigh,
                indicatorColor: couleurs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
