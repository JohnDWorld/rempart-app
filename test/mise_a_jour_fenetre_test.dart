import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/core/constants/update_constants.dart';

void main() {
  final maintenant = DateTime(2026, 8, 24, 18);

  group('doitVerifier', () {
    test('vérifie à la première ouverture', () {
      // Jamais vérifié : c'est précisément le moment où l'on veut savoir.
      expect(doitVerifier(derniere: null, maintenant: maintenant), isTrue);
    });

    test('se tait dans la fenêtre', () {
      expect(
        doitVerifier(
          derniere: maintenant.subtract(const Duration(hours: 5, minutes: 59)),
          maintenant: maintenant,
        ),
        isFalse,
      );
    });

    test('vérifie une fois la fenêtre écoulée', () {
      expect(
        doitVerifier(
          derniere: maintenant.subtract(const Duration(hours: 6)),
          maintenant: maintenant,
        ),
        isTrue,
      );
      expect(
        doitVerifier(
          derniere: maintenant.subtract(const Duration(days: 3)),
          maintenant: maintenant,
        ),
        isTrue,
      );
    });

    test("une horloge qui recule ne bloque pas l'app pour toujours", () {
      // Horodatage dans le futur (changement d'heure, horloge corrigée) :
      // la différence est négative, donc inférieure à l'intervalle, et la
      // vérification attend. C'est le comportement voulu, pas un blocage :
      // le bouton des paramètres reste disponible.
      expect(
        doitVerifier(
          derniere: maintenant.add(const Duration(days: 1)),
          maintenant: maintenant,
        ),
        isFalse,
      );
    });
  });
}
