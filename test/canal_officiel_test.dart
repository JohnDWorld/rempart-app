import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/core/utils/canal_officiel.dart';

/// Canal officiel : absent des destinations d'envoi.
typedef _Salon = ({String id, bool canal, bool ecriture});

_Salon _s(String id, {bool canal = false, bool ecriture = true}) =>
    (id: id, canal: canal, ecriture: ecriture);

void main() {
  group('destinationsEnvoi', () {
    test('écarte le canal et les salons en lecture seule', () {
      final r = destinationsEnvoi<_Salon>(
        [
          _s('a'),
          _s('canal', canal: true, ecriture: false),
          _s('lecture', ecriture: false),
          _s('canalEcrivable', canal: true),
        ],
        estCanal: (s) => s.canal,
        peutEcrire: (s) => s.ecriture,
      );
      expect(r.map((s) => s.id), ['a']);
    });
  });
}
