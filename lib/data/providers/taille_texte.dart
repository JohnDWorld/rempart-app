import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Taille du texte des messages, au choix de l'utilisateur.
///
/// Le réglage système d'Android ou d'iOS s'applique par-dessus celui-ci et
/// n'est pas remplacé : une personne qui a agrandi tout son téléphone garde
/// son agrandissement, et peut encore grossir les messages seuls. C'est
/// pourquoi le facteur porte sur la taille de base du texte plutôt que sur le
/// `textScaler`, qui écraserait le réglage d'accessibilité.
enum TailleTexte {
  petite('Petite', 0.87),
  normale('Normale', 1),
  grande('Grande', 1.15),
  tresGrande('Très grande', 1.3);

  const TailleTexte(this.libelle, this.facteur);

  final String libelle;

  /// Multiplie la taille de base des messages.
  final double facteur;
}

/// Taille courante. Injectée au démarrage par `main.dart` (voir
/// [chargerTailleTexte]) : lue plus tard, le premier rendu des conversations
/// se ferait dans la taille par défaut puis sauterait.
final tailleTexteProvider =
    StateProvider<TailleTexte>((ref) => TailleTexte.normale);

const _cle = 'taille_texte';

Future<TailleTexte> chargerTailleTexte() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final nom = prefs.getString(_cle);
    return TailleTexte.values.firstWhere(
      (t) => t.name == nom,
      orElse: () => TailleTexte.normale,
    );
  } catch (_) {
    return TailleTexte.normale;
  }
}

/// Best-effort : sans persistance, le choix vaut pour la session, ce qui vaut
/// mieux que de le refuser.
Future<void> enregistrerTailleTexte(TailleTexte taille) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cle, taille.name);
  } catch (_) {}
}
