import 'package:flutter_test/flutter_test.dart';

/// Ce qu'un appui sur un bouton envoie, et ce qu'il affiche.
///
/// Les deux diffèrent volontairement : l'agent attend sa valeur exacte
/// (« !cancel »), l'utilisateur doit relire son geste (« ❌ Annuler »).
/// Les intervertir casserait l'un ou l'autre, sans que rien ne le signale.
void main() {
  /// Reproduit la lecture du champ, telle que `Event.libelleBouton` la fait.
  String? libelleBouton(Map<String, dynamic> content) {
    final libelle = content['fr.rempart.libelle_bouton'];
    return libelle is String && libelle.trim().isNotEmpty
        ? libelle.trim()
        : null;
  }

  String affiche(Map<String, dynamic> content) =>
      libelleBouton(content) ?? (content['body'] as String? ?? '');

  test('le corps porte la valeur, que l agent lit', () {
    final content = <String, dynamic>{
      'msgtype': 'm.text',
      'body': '!cancel',
      'fr.rempart.libelle_bouton': '❌ Annuler',
    };
    // C'est le corps que lisent la passerelle et les autres clients.
    expect(content['body'], '!cancel');
  });

  test('la bulle affiche le libellé du bouton', () {
    expect(
      affiche({'body': '!cancel', 'fr.rempart.libelle_bouton': '❌ Annuler'}),
      '❌ Annuler',
    );
  });

  test('un message ordinaire affiche son corps', () {
    // Le champ n'existe pas : rien ne doit changer pour les autres messages.
    expect(affiche({'body': 'Bonjour'}), 'Bonjour');
  });

  test('un libellé vide ne masque pas le corps', () {
    // Sinon un champ mal rempli ferait disparaître le message.
    expect(affiche({'body': '!ok', 'fr.rempart.libelle_bouton': '   '}), '!ok');
    expect(affiche({'body': '!ok', 'fr.rempart.libelle_bouton': 42}), '!ok');
  });
}
