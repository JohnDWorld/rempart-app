import 'package:flutter_test/flutter_test.dart';

/// Une conversation qu'on vient de lire ne doit plus paraître non lue.
///
/// Le compteur vient du serveur et ne retombe qu'au sync suivant : on le
/// tempère avec le dernier message lu localement. La règle doit tenir dans
/// les deux sens, sans quoi on troque un défaut contre un autre — une
/// conversation qui reste en gras, ou un nouveau message qui passe inaperçu.
void main() {
  /// Reproduit la décision de `ConversationTile`.
  bool nonLue({
    required int compteurServeur,
    required String? dernierEvenement,
    required String? dernierLuLocalement,
  }) {
    return compteurServeur > 0 &&
        (dernierLuLocalement == null || dernierEvenement != dernierLuLocalement);
  }

  test('jamais ouverte : non lue', () {
    expect(
      nonLue(
        compteurServeur: 3,
        dernierEvenement: r'$abc',
        dernierLuLocalement: null,
      ),
      isTrue,
    );
  });

  test("qu'on vient de lire : lue, sans attendre le serveur", () {
    // Le compteur du serveur dit encore 3, mais on a lu jusqu'au dernier.
    expect(
      nonLue(
        compteurServeur: 3,
        dernierEvenement: r'$abc',
        dernierLuLocalement: r'$abc',
      ),
      isFalse,
    );
  });

  test('un nouveau message la remet en non lue, toute seule', () {
    // C'est pourquoi on retient un identifiant et non un drapeau : rien à
    // effacer, l'arrivée d'un message suffit.
    expect(
      nonLue(
        compteurServeur: 1,
        dernierEvenement: r'$nouveau',
        dernierLuLocalement: r'$abc',
      ),
      isTrue,
    );
  });

  test('sans rien à lire, le souvenir ne crée pas de non-lu', () {
    expect(
      nonLue(
        compteurServeur: 0,
        dernierEvenement: r'$abc',
        dernierLuLocalement: r'$vieux',
      ),
      isFalse,
    );
  });
}
