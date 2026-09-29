import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/core/utils/demandes.dart';

/// Demandes de message : qui entre d'office, et ce qu'on en annonce.
///
/// Avant le 2026-09-28, toute invitation était acceptée au sync suivant :
/// n'importe quel inscrit pouvait écrire à n'importe qui, ou l'ajouter à un
/// groupe, sans que rien ne lui soit demandé.
void main() {
  group('inviteurConnu', () {
    const bere = '@u_924330b62a3f4e04934b0b6169afdbfc:rempart-messenger.fr';
    const inconnu = '@u_0123456789abcdef0123456789abcdef:rempart-messenger.fr';
    const agent = '@heimdall:rempart-messenger.fr';

    test('un tête-à-tête existant suffit', () {
      expect(
        inviteurConnu(
          bere,
          tetesATetes: {
            bere: ['!a:x'],
          },
          mesBots: {},
        ),
        isTrue,
      );
    });

    test('un de mes bots est connu sans conversation', () {
      expect(inviteurConnu(agent, tetesATetes: {}, mesBots: {agent}), isTrue);
    });

    test('un inconnu reste une demande', () {
      expect(
        inviteurConnu(
          inconnu,
          tetesATetes: {
            bere: ['!a:x'],
          },
          mesBots: {agent},
        ),
        isFalse,
      );
    });
  });

  group('apercuDemande', () {
    test('tête-à-tête : le nom dans le corps, jamais le message', () {
      final a = apercuDemande(nomInviteur: 'Bérénice');
      expect(a.titre, 'Demande de message');
      expect(a.corps, 'Bérénice souhaite vous écrire');
    });

    test('groupe : le groupe est nommé', () {
      final a = apercuDemande(nomInviteur: 'Bérénice', nomGroupe: 'Famille');
      expect(a.titre, 'Invitation dans un groupe');
      expect(a.corps, 'Bérénice vous invite dans « Famille »');
    });

    test('sans nom lisible : jamais un identifiant', () {
      expect(apercuDemande().corps, "Quelqu'un souhaite vous écrire");
      expect(
        apercuDemande(nomGroupe: 'Famille').corps,
        "Quelqu'un vous invite dans « Famille »",
      );
    });
  });

  test('libelleDemandes accorde le pluriel', () {
    expect(libelleDemandes(1), '1 demande de message');
    expect(libelleDemandes(3), '3 demandes de message');
  });
}
