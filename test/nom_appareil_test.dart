import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/core/utils/nom_appareil.dart';

void main() {
  // Signatures réelles, relevées sur les navigateurs concernés.
  const opera = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, '
      'like Gecko) Chrome/151.0.0.0 Safari/537.36 OPR/135.0.0.0';
  const chrome = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, '
      'like Gecko) Chrome/153.0.0.0 Safari/537.36';
  const edge = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36 Edg/140.0.0.0';
  const firefox = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) '
      'Gecko/20100101 Firefox/140.0';
  const safariMac = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15';
  const chromeAndroid = 'Mozilla/5.0 (Linux; Android 15; Pixel 8) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Mobile '
      'Safari/537.36';
  const safariIphone = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 '
      'Safari/604.1';

  test('navigateur et système lus dans la signature', () {
    expect(lireUserAgent(opera), ('Opera', 'Linux'));
    expect(lireUserAgent(chrome), ('Chrome', 'Linux'));
    expect(lireUserAgent(edge), ('Edge', 'Windows'));
    expect(lireUserAgent(firefox), ('Firefox', 'Windows'));
    expect(lireUserAgent(safariMac), ('Safari', 'macOS'));
    expect(lireUserAgent(chromeAndroid), ('Chrome', 'Android'));
    expect(lireUserAgent(safariIphone), ('Safari', 'iOS'));
    expect(lireUserAgent(''), ('Navigateur', null));
  });

  test("le nom de l'appareil", () {
    expect(nomAppareil(android: true, ios: false), 'Rempart · Android');
    expect(nomAppareil(android: false, ios: true), 'Rempart · iOS');
    expect(
      nomAppareil(android: false, ios: false, userAgent: opera),
      'Rempart · Opera (Linux)',
    );
    expect(nomAppareil(android: false, ios: false), 'Rempart · Navigateur');
  });

  test('la liste relit le nom : icône, titre et pastille', () {
    expect(decrireAppareil('Rempart · Android'), (
      genre: GenreAppareil.telephone,
      titre: 'Application Android',
      pastille: 'Android',
    ));
    expect(decrireAppareil('Rempart · iOS').pastille, 'iOS');
    expect(decrireAppareil('Rempart · Opera (Linux)'), (
      genre: GenreAppareil.navigateur,
      titre: 'Opera sur Linux',
      pastille: 'Opera',
    ));
    expect(decrireAppareil('Rempart · Navigateur').titre, 'Navigateur');
  });

  test("ce qui n'est pas de nous s'affiche tel quel, sans pastille", () {
    for (final nom in ['Rempart Messenger', 'Element Web: Firefox on Linux']) {
      final d = decrireAppareil(nom);
      expect(d.genre, GenreAppareil.inconnu);
      expect(d.titre, nom);
      expect(d.pastille, isNull);
    }
    expect(decrireAppareil(null).titre, 'Appareil sans nom');
  });

  test('aller-retour : tout nom posé se relit', () {
    for (final ua in [opera, chrome, edge, firefox, safariMac, chromeAndroid]) {
      final nom = nomAppareil(android: false, ios: false, userAgent: ua);
      expect(decrireAppareil(nom).genre, GenreAppareil.navigateur, reason: nom);
    }
  });
}
