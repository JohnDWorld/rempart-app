import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/core/constants/app_constants.dart';

void main() {
  group('urlDeSoutienValide', () {
    test("absente ou vide, le soutien n'existe pas", () {
      expect(urlDeSoutienValide(null), isEmpty);
      expect(urlDeSoutienValide(''), isEmpty);
      // Le piège du fichier édité à la main : une valeur qui n'est que des
      // espaces ferait apparaître une entrée menant dans le vide.
      expect(urlDeSoutienValide('   '), isEmpty);
    });

    test('une adresse https est retenue', () {
      expect(
        urlDeSoutienValide('https://rempart.fr/soutenir'),
        'https://rempart.fr/soutenir',
      );
      expect(urlDeSoutienValide('  https://rempart.fr/don  '),
          'https://rempart.fr/don');
    });

    test("tout ce qui n'est pas https est refusé", () {
      for (final valeur in [
        'http://rempart.fr/soutenir',
        'javascript:alert(1)',
        'rempart.fr/soutenir',
        'https://',
      ]) {
        expect(urlDeSoutienValide(valeur), isEmpty,
            reason: 'refuser « $valeur »');
      }
    });
  });
}
