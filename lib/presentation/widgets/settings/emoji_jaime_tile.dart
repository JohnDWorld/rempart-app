import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers/emoji_jaime.dart';
import '../chat/choix_emoji.dart';

/// Réglage de l'emoji posé par « j'aime » (pouce ou double appui) : tous les
/// emojis, les derniers choisis en tête.
class EmojiJaimeTile extends ConsumerWidget {
  const EmojiJaimeTile({super.key});

  Future<void> _choisir(BuildContext context, WidgetRef ref) async {
    final messager = ScaffoldMessenger.of(context);
    final choix = await choisirEmoji(context);
    if (choix == null) return;
    if (!emojiJaimeAccepte(choix)) {
      messager.showSnackBar(
        const SnackBar(content: Text('❌ est déjà le pouce en bas')),
      );
      return;
    }
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
