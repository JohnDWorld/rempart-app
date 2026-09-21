import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/data/models/matrix_extensions.dart';

void main() {
  group('estUnIdentifiant', () {
    test('reconnaît un mxid complet et son localpart', () {
      const mxid = '@u_cac4cfdb367a40668f816e51487fb3bf:100.64.0.10';
      expect(estUnIdentifiant(mxid, mxid), isTrue);
      expect(
        estUnIdentifiant('u_cac4cfdb367a40668f816e51487fb3bf', mxid),
        isTrue,
      );
    });

    test('laisse passer un vrai nom', () {
      const mxid = '@u_cac4cfdb367a40668f816e51487fb3bf:100.64.0.10';
      expect(estUnIdentifiant('Bérénice', mxid), isFalse);
    });

    test("laisse passer le nom d'un bot, qui EST son localpart", () {
      // Un bot s'appelle vraiment « hermes_bot » : le nom coïncide avec le
      // localpart sans être pour autant un identifiant illisible.
      const mxid = '@hermes_bot:100.64.0.10';
      expect(estUnIdentifiant('hermes_bot', mxid), isFalse);
    });
  });
}
