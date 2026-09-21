import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/data/providers/vitesse_vocal.dart';

void main() {
  group('vitesseSuivante', () {
    test('parcourt les crans puis revient au debut', () {
      expect(vitesseSuivante(1), 1.5);
      expect(vitesseSuivante(1.5), 2);
      expect(vitesseSuivante(2), 1);
    });

    test('une vitesse inconnue ramene au premier cran', () {
      // Sans le repli, `indexOf` rendrait -1 et le bouton resterait coince.
      expect(vitesseSuivante(3), 1);
    });
  });

  group('libelleVitesseVocal', () {
    test('sans decimale inutile, et virgule francaise', () {
      expect(libelleVitesseVocal(1), 'x1');
      expect(libelleVitesseVocal(1.5), 'x1,5');
      expect(libelleVitesseVocal(2), 'x2');
    });
  });
}
