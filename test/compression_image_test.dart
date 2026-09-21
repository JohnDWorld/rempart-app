import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/data/services/compression_image.dart';

/// Ce qu'on allège, et ce qu'on laisse tranquille.
///
/// La compression touche des photos que l'utilisateur ne reverra pas en
/// original : se tromper de cible abîme une image sans recours.
void main() {
  group('poidsLisible', () {
    test('les petits fichiers en kilo-octets', () {
      expect(CompressionImage.poidsLisible(150 * 1024), '150 Ko');
    });

    test('les gros en mega-octets, avec une décimale', () {
      expect(CompressionImage.poidsLisible(3 * 1024 * 1024), '3.0 Mo');
    });

    test('la bascule se fait à un mega-octet', () {
      expect(CompressionImage.poidsLisible(1024 * 1024 - 1), '1024 Ko');
      expect(CompressionImage.poidsLisible(1024 * 1024), '1.0 Mo');
    });
  });
}
