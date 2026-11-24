import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers/emoji_jaime.dart';
import '../adaptive/adaptive.dart';

/// Réglage de l'emoji posé par « j'aime » (pouce ou double appui).
class EmojiJaimeTile extends ConsumerWidget {
  const EmojiJaimeTile({super.key});

  Future<void> _choisir(BuildContext context, WidgetRef ref) async {
    final actuel = ref.read(emojiJaimeProvider);
    final choix = await feuilleAdaptative<String>(
      context: context,
      // Les widgets Material ont besoin d'un Material ancêtre dans un contexte
      // Cupertino, où la feuille n'en fournit pas.
      builder: (context) => Material(
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Emoji du j'aime",
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final emoji in emojisJaime)
                      ChoiceChip(
                        label:
                            Text(emoji, style: const TextStyle(fontSize: 24)),
                        selected: emoji == actuel,
                        showCheckmark: false,
                        onSelected: (_) => Navigator.pop(context, emoji),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (choix == null) return;
    ref.read(emojiJaimeProvider.notifier).state = choix;
    await enregistrerEmojiJaime(choix);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emoji = ref.watch(emojiJaimeProvider);
    return ListTile(
      leading: const Icon(Icons.thumb_up_outlined),
      title: const Text("Emoji du j'aime"),
      subtitle: const Text('Pouce ou double appui sous un message'),
      trailing: Text(emoji, style: const TextStyle(fontSize: 22)),
      onTap: () => _choisir(context, ref),
    );
  }
}
