import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:rempart_app/core/utils/lectures.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  final envoye = DateTime(2026, 10, 6, 18, 33, 2);

  test('lu si le dernier accusé suit l envoi, dans l ordre de lecture', () {
    final l = lecturesDe(
      envoye: envoye,
      accuses: {
        '@lea:r': DateTime(2026, 10, 6, 18, 50),
        '@hugo:r': DateTime(2026, 10, 6, 18, 41),
        '@ines:r': DateTime(2026, 10, 6, 18, 20), // a lu AVANT l'envoi
      },
      destinataires: ['@lea:r', '@hugo:r', '@ines:r', '@camille:r'],
    );
    expect(l.lu.map((x) => x.mxid), ['@hugo:r', '@lea:r']);
    expect(l.lu.first.quand, DateTime(2026, 10, 6, 18, 41));
    expect(l.pasLu, ['@ines:r', '@camille:r']);
  });

  test('un accusé à la seconde même de l envoi compte comme lu', () {
    final l = lecturesDe(
      envoye: envoye,
      accuses: {'@lea:r': envoye},
      destinataires: ['@lea:r'],
    );
    expect(l.lu.single.mxid, '@lea:r');
    expect(l.pasLu, isEmpty);
  });

  test('un accusé d un ancien membre ne fait pas apparaître un inconnu', () {
    final l = lecturesDe(
      envoye: envoye,
      accuses: {'@parti:r': DateTime(2026, 10, 6, 19)},
      destinataires: ['@lea:r'],
    );
    expect(l.lu, isEmpty);
    expect(l.pasLu, ['@lea:r']);
  });

  test('l heure se dit comme dans une conversation', () {
    final maintenant = DateTime(2026, 10, 7, 9, 15);
    expect(quandLisible(DateTime(2026, 10, 7, 8, 5), maintenant), "aujourd'hui à 08:05");
    expect(quandLisible(DateTime(2026, 10, 6, 18, 41), maintenant), 'hier à 18:41');
    expect(quandLisible(DateTime(2026, 9, 28, 7), maintenant), '28 sept. 2026 à 07:00');
  });

  test('l envoi se date en entier, à la seconde', () {
    expect(dateComplete(envoye), 'mardi 6 octobre 2026 à 18:33:02');
  });
}
