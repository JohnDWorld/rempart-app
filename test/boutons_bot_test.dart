import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/presentation/widgets/chat/message_bubble.dart';

/// Lecture du champ `fr.rempart.boutons`, qui vient d'un tiers.
///
/// La passerelle borne ce qu'elle envoie (huit boutons, libellés de 40
/// caractères, valeurs de 200), mais n'importe quel client Matrix peut poser
/// le champ tel qu'il veut : l'application applique les mêmes bornes, sans
/// quoi des milliers de boutons gelaient l'écran de tout le salon.
void main() {
  Map<String, dynamic> contenu(List<Object?> boutons) =>
      {'body': 'choisis', 'fr.rempart.boutons': boutons};

  test('huit boutons au plus', () {
    final brut = [
      for (var i = 0; i < 5000; i++) {'texte': 'b$i', 'valeur': 'v$i'},
    ];
    final boutons = boutonsDuContenu(contenu(brut));
    expect(boutons.length, 8);
    expect(boutons.first.texte, 'b0');
    expect(boutons.last.valeur, 'v7');
  });

  test('libellé et valeur bornés', () {
    final boutons = boutonsDuContenu(
      contenu([
        {'texte': 'x' * 1000, 'valeur': 'y' * 1000},
      ]),
    );
    expect(boutons.single.texte.length, 40);
    expect(boutons.single.valeur.length, 200);
  });

  test('un bouton mal formé est ignoré, pas fatal', () {
    final boutons = boutonsDuContenu(
      contenu([
        {'texte': 123, 'valeur': 'v'},
        {'texte': 'sans valeur'},
        'pas un objet',
        null,
        {'texte': ' ok ', 'valeur': ' !ok '},
      ]),
    );
    expect(boutons.length, 1);
    expect(boutons.single.texte, 'ok');
    expect(boutons.single.valeur, '!ok');
  });

  test('sans champ, ou champ vide : aucun bouton', () {
    expect(boutonsDuContenu({'body': 'x'}), isEmpty);
    expect(boutonsDuContenu(contenu([])), isEmpty);
    expect(boutonsDuContenu({'fr.rempart.boutons': 'nimporte'}), isEmpty);
  });
}
