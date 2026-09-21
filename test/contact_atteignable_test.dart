import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:rempart_app/data/models/matrix_extensions.dart';

void main() {
  group('contactAtteignable', () {
    test('accepte un contact présent ou invité', () {
      expect(contactAtteignable(Membership.join), isTrue);
      expect(contactAtteignable(Membership.invite), isTrue);
    });

    test('écarte la room que le contact a quittée', () {
      // Le bug d'origine : notre propre appartenance donnait le change, et les
      // messages partaient dans une room où plus personne ne les lisait.
      expect(contactAtteignable(Membership.leave), isFalse);
      expect(contactAtteignable(Membership.ban), isFalse);
    });

    test("écarte un contact qui n'a fait que frapper à la porte", () {
      expect(contactAtteignable(Membership.knock), isFalse);
    });

    test('accepte dans le doute', () {
      // Serveur injoignable : écarter la room fabriquerait un fil en double à
      // chaque tentative, alors que rien ne prouve un départ.
      expect(contactAtteignable(null), isTrue);
    });
  });
}
