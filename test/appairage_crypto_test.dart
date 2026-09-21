import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/core/utils/appairage_crypto.dart';

void main() {
  group('appairage', () {
    // Le même vecteur est rejoué dans `test_appairage.py`. Les deux
    // implémentations dérivent leurs clés séparément : sans ce garde-fou, une
    // divergence n'apparaîtrait qu'au premier appairage réel, sous la forme
    // d'un « paquet altéré » que personne ne saurait expliquer.
    final secret = Uint8List.fromList(List<int>.generate(32, (i) => i));

    test('dérive exactement les mêmes clés que la passerelle', () {
      final cles = deriverCles(secret);
      expect(
        cles.chiffrement.map((o) => o.toRadixString(16).padLeft(2, '0')).join(),
        'dc04d480e8067fa58c106cf7f107ab067faf112587e6182818a7906f4cafcb63',
      );
      expect(
        cles.authentification
            .map((o) => o.toRadixString(16).padLeft(2, '0'))
            .join(),
        '3bd8242fbb2bb07ab67f86e59e334cca847efad5f770c8cbfbe74d6d217d161d',
      );
    });

    test('rejette un paquet dont le sceau ne correspond pas', () {
      final cles = deriverCles(secret);
      final iv = Uint8List.fromList(
        [...List<int>.generate(8, (i) => i), ...List<int>.filled(8, 0)],
      );
      final chiffre = Uint8List.fromList([1, 2, 3, 4]);
      final paquet = {
        'iv': base64.encode(iv),
        'chiffre': base64.encode(chiffre),
        // Sceau calculé avec la mauvaise clé : c'est exactement ce que
        // produirait un tiers qui bricole le paquet.
        'mac': base64.encode(cles.chiffrement),
      };
      expect(() => ouvrirPaquet(secret, paquet), throwsFormatException);
    });

    test('un secret ne survit pas à un aller-retour de texte abîmé', () {
      expect(secretDepuisTexte(secretEnTexte(secret)), secret);
      expect(() => secretDepuisTexte('trop-court'), throwsFormatException);
    });

    test('chiffre exactement comme la passerelle', () {
      // Le mode compteur admet plusieurs conventions : si les deux côtés n'en
      // retiennent pas la même, tout paraît fonctionner jusqu'au premier
      // appairage, qui échoue alors sans rien expliquer. Vecteur produit par
      // `test_appairage.py`.
      final cles = deriverCles(secret);
      final iv = Uint8List.fromList(
        [...List<int>.generate(8, (i) => i), ...List<int>.filled(8, 0)],
      );
      final paquet = scellerPourTest(cles, iv, utf8.encode('bonjour'));
      expect(
        paquet.map((o) => o.toRadixString(16).padLeft(2, '0')).join(),
        '9f6ac7d5e9b5bd',
      );
    });

    test("l'empreinte est celle que la passerelle attend", () {
      // sha256 des octets 0..31, en hexadécimal.
      expect(
        empreinteDe(secret),
        '630dcd2966c4336691125448bbb25b4ff412a49c732db2c8abc1b8581bd710dd',
      );
    });
  });
}
