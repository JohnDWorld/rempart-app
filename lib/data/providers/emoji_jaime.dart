import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// L'emoji que pose « j'aime » : le pouce sous un message reçu, et le double
/// appui sur lui. 👍 par défaut, au choix dans les paramètres.
///
/// ❌ n'est pas proposé : c'est déjà le pouce en bas, et les deux boutons
/// poseraient la même réaction.
const emojisJaime = ['👍', '❤️', '🔥', '😂', '😮', '🙏', '👏', '✅'];

/// Choix courant. Injecté au démarrage par `main.dart` (voir
/// [chargerEmojiJaime]), comme la taille du texte.
final emojiJaimeProvider = StateProvider<String>((ref) => emojisJaime.first);

const _cle = 'emoji_jaime';

Future<String> chargerEmojiJaime() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final emoji = prefs.getString(_cle);
    // Un emoji retiré de la liste depuis ramène au défaut.
    return emojisJaime.contains(emoji) ? emoji! : emojisJaime.first;
  } catch (_) {
    return emojisJaime.first;
  }
}

/// Best-effort : sans persistance, le choix vaut pour la session.
Future<void> enregistrerEmojiJaime(String emoji) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cle, emoji);
  } catch (_) {}
}
