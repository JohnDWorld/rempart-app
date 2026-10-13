import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/data/services/lecteur_vocal.dart';

/// Une bulle ne voit que l'état de SON vocal. Quand l'état vivait dans la
/// bulle, un message reçu pendant une écoute le faisait passer à la bulle
/// voisine : on voyait avancer le deuxième vocal, on entendait le premier.
void main() {
  final lecteur = LecteurVocal.instance;

  tearDown(lecteur.etatPourTest);

  test('le vocal qui joue est le seul à se dire en lecture', () {
    lecteur.etatPourTest(
      cle: 'premier',
      joue: true,
      position: const Duration(seconds: 3),
    );
    expect(lecteur.joue('premier'), isTrue);
    expect(lecteur.position('premier'), const Duration(seconds: 3));
    expect(lecteur.joue('deuxieme'), isFalse);
    expect(lecteur.position('deuxieme'), Duration.zero);
  });

  test('sans vocal armé, aucune bulle ne joue', () {
    expect(lecteur.joue('premier'), isFalse);
    expect(lecteur.position('premier'), Duration.zero);
  });
}
