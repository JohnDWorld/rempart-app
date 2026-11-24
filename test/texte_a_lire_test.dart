import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/core/utils/texte_a_lire.dart';

void main() {
  test('un message court part d’un seul morceau', () {
    expect(morceauxALire('Bonjour. Ça va ?'), ['Bonjour. Ça va ?']);
  });

  test('une adresse se lit « lien », pas caractère par caractère', () {
    expect(
      morceauxALire('Source : https://exemple.fr/a?b=1 et www.test.fr.'),
      ['Source : lien et lien.'],
    );
  });

  test('un texte vide ne lit rien', () {
    expect(morceauxALire('  \n '), isEmpty);
  });

  test('un long texte est coupé entre deux phrases, sans rien perdre', () {
    final phrase = 'Voici une phrase de test assez ordinaire. ';
    final texte = phrase * 200; // 8 400 caractères
    final morceaux = morceauxALire(texte, max: 1000);
    expect(morceaux.length, greaterThan(8));
    for (final m in morceaux) {
      expect(m.length, lessThanOrEqualTo(1000));
      expect(m, endsWith('.'));
    }
    expect(morceaux.join(' '), texte.trim());
  });

  test('une phrase sans fin se coupe entre deux mots, à défaut au milieu', () {
    final mots = 'mot ' * 600;
    final morceaux = morceauxALire(mots, max: 100);
    expect(morceaux.every((m) => m.length <= 100), isTrue);
    expect(morceaux.join(' '), mots.trim());

    final bloc = 'x' * 250;
    expect(morceauxALire(bloc, max: 100).map((m) => m.length), [100, 100, 50]);
  });
}
