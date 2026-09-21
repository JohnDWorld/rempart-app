import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/data/services/reinitialisation_e2e.dart';

/// La coupure décide de ce qui disparaît du fil. Une erreur de sens ici
/// masquerait des messages parfaitement lisibles, ou laisserait le fil se
/// remplir d'erreurs de déchiffrement que rien n'expliquerait.
void main() {
  final coupure = DateTime.utc(2026, 9, 20, 12);

  setUp(ReinitialisationE2e.oublier);

  test('un message reçu avant la réinitialisation est perdu', () {
    expect(
      ReinitialisationE2e.avantLaCoupure(
        coupure.subtract(const Duration(seconds: 1)),
        coupure: coupure,
      ),
      isTrue,
    );
  });

  test('un message reçu après reste lisible', () {
    expect(
      ReinitialisationE2e.avantLaCoupure(
        coupure.add(const Duration(seconds: 1)),
        coupure: coupure,
      ),
      isFalse,
    );
  });

  test("sans réinitialisation, rien n'est masqué", () {
    expect(
      ReinitialisationE2e.avantLaCoupure(DateTime.utc(1990)),
      isFalse,
    );
  });
}
