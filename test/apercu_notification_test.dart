import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/core/utils/apercu_notification.dart';

void main() {
  group('composerApercu', () {
    test('tête-à-tête : le contact en titre, le message en corps', () {
      final a = composerApercu(texte: 'On se voit à 18h ?', nomExpediteur: 'Bérénice');
      expect(a.titre, 'Bérénice');
      expect(a.corps, 'On se voit à 18h ?');
    });

    test("groupe : le groupe en titre, l'auteur devant le message", () {
      final a = composerApercu(
        texte: 'je suis en route',
        nomExpediteur: 'Bérénice',
        nomRoom: 'Vacances',
      );
      expect(a.titre, 'Vacances');
      expect(a.corps, 'Bérénice : je suis en route');
    });

    test("un secret reste masqué, l'expéditeur reste annoncé", () {
      final a = composerApercu(
        texte: "Le code d'entrée est 0672",
        nomExpediteur: 'Bérénice',
      );
      expect(a.titre, 'Bérénice');
      expect(a.corps, 'Message masqué');

      final groupe = composerApercu(
        texte: 'mot de passe du wifi : Maison2026x',
        nomExpediteur: 'Bérénice',
        nomRoom: 'Coloc',
      );
      expect(groupe.corps, 'Bérénice : Message masqué');
    });

    test('aucun nom lisible : jamais un identifiant en repli', () {
      final a = composerApercu(texte: 'Coucou');
      expect(a.titre, 'Rempart');
      expect(a.corps, 'Coucou');

      final groupe = composerApercu(texte: 'Coucou', nomRoom: 'Vacances');
      expect(groupe.titre, 'Vacances');
      expect(groupe.corps, 'Coucou', reason: 'pas de « null : » devant');
    });
  });
}
