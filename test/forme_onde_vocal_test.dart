import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/data/services/enregistreur_vocal.dart';

/// La silhouette d'un vocal, calculée à l'enregistrement.
///
/// Elle voyage dans l'événement et n'est jamais recalculée : une erreur ici
/// part avec le message et ne se rattrape plus.
void main() {
  group('silhouette', () {
    test('sans mesure, rien à dessiner', () {
      expect(EnregistreurVocal.silhouette([]), isEmpty);
    });

    test('reste dans les bornes de la convention (0 à 1024)', () {
      final forme = EnregistreurVocal.silhouette(
        [for (var i = 0; i < 200; i++) -i.toDouble()],
      );
      expect(forme, isNotEmpty);
      expect(forme.every((v) => v >= 0 && v <= 1024), isTrue);
    });

    test('le plus fort atteint le maximum, quel que soit le niveau', () {
      // Deux enregistrements du même son, l'un fait de loin : ils doivent
      // dessiner la même chose, sinon un vocal murmuré paraîtrait plat.
      final proche = EnregistreurVocal.silhouette([-6, -20, -6, -40]);
      final lointain = EnregistreurVocal.silhouette([-26, -40, -26, -60]);
      expect(proche.reduce((a, b) => a > b ? a : b), 1024);
      expect(lointain.reduce((a, b) => a > b ? a : b), 1024);
    });

    test('un vocal court ne fabrique pas de barres qu il n a pas', () {
      // Trois mesures ne peuvent pas donner 48 barres : les étirer inventerait
      // une silhouette que personne n'a prononcée.
      expect(EnregistreurVocal.silhouette([-10, -20, -30]).length, 3);
    });

    test('les mesures nombreuses sont ramenées au nombre de barres', () {
      final forme = EnregistreurVocal.silhouette(
        List<double>.filled(600, -10),
        barres: 32,
      );
      expect(forme.length, 32);
    });

    test('le silence ne remonte pas au maximum', () {
      // Sous le plancher de -50 dB, tout est silence : sans le plancher, le
      // bruit de fond d'une pièce vide dessinerait une parole.
      final forme = EnregistreurVocal.silhouette([-6, -80, -6, -90]);
      expect(forme[1], lessThan(50));
      expect(forme[3], lessThan(50));
    });

    test('une valeur aberrante ne fait pas tout sauter', () {
      // -infinity arrive quand le micro n'a rien capté du tout.
      final forme = EnregistreurVocal.silhouette([
        double.negativeInfinity,
        -6,
        double.nan,
      ]);
      expect(forme.length, 3);
      expect(forme.every((v) => v >= 0 && v <= 1024), isTrue);
    });

    test('un silence complet ne divise pas par zero', () {
      final forme = EnregistreurVocal.silhouette([-100, -100, -100]);
      expect(forme, everyElement(0));
    });
  });
}
