import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// L'emoji que pose « j'aime » : le pouce sous un message reçu, et le double
/// appui sur lui. 👍 par défaut, n'importe quel emoji au choix dans les
/// paramètres.
const emojiJaimeParDefaut = '👍';

/// ❌ est refusé : c'est déjà le pouce en bas, et les deux boutons poseraient
/// la même réaction.
bool emojiJaimeAccepte(String? emoji) =>
    emoji != null && emoji.trim().isNotEmpty && emoji != '❌';

/// Choix courant. Injecté au démarrage par `main.dart` (voir
/// [chargerEmojiJaime]), comme la taille du texte.
final emojiJaimeProvider = StateProvider<String>((ref) => emojiJaimeParDefaut);

const _cle = 'emoji_jaime';

Future<String> chargerEmojiJaime() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final emoji = prefs.getString(_cle);
    return emojiJaimeAccepte(emoji) ? emoji! : emojiJaimeParDefaut;
  } catch (_) {
    return emojiJaimeParDefaut;
  }
}

/// Best-effort : sans persistance, le choix vaut pour la session.
Future<void> enregistrerEmojiJaime(String emoji) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cle, emoji);
  } catch (_) {}
}
