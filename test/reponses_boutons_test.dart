import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:rempart_app/core/utils/reponse_bouton.dart';

/// Base factice : le client n'y touche pas pour ce qu'on vérifie ici.
class _BaseFactice implements DatabaseApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const moi = '@john:rempart.test';
  final room = Room(
    id: '!sindri:rempart.test',
    client: Client('test', database: _BaseFactice()),
  );

  var numero = 0;
  Event message(
    String expediteur,
    Map<String, Object?> contenu, {
    EventStatus statut = EventStatus.synced,
  }) =>
      Event(
        type: EventTypes.Message,
        content: contenu,
        room: room,
        eventId: '\$m${numero++}',
        senderId: expediteur,
        originServerTs: DateTime(2026, 11, 25),
        status: statut,
      );

  Event reponse(String question, String libelle, {EventStatus? statut}) =>
      message(
        moi,
        contenuReponseBouton(
          valeur: '!fusion',
          libelle: libelle,
          questionId: question,
        ),
        statut: statut ?? EventStatus.synced,
      );

  test('ma réponse retire les boutons de sa question, et seulement elle', () {
    final reponses = reponsesAuxBoutons([
      reponse(r'$q3', 'Fusionner 3 et 10'),
      message('@sindri:rempart.test', {'msgtype': 'm.text', 'body': 'Q4'}),
    ], moi);
    expect(reponses, {r'$q3': 'Fusionner 3 et 10'});
  });

  test('la réponse d un autre membre ne retire pas mes boutons', () {
    final autre = message(
      '@lea:rempart.test',
      contenuReponseBouton(valeur: 'ok', libelle: 'OK', questionId: r'$q'),
    );
    expect(reponsesAuxBoutons([autre], moi), isEmpty);
  });

  test('une réponse en échec laisse les boutons, pour réessayer', () {
    expect(
      reponsesAuxBoutons(
        [reponse(r'$q', 'Valider', statut: EventStatus.error)],
        moi,
      ),
      isEmpty,
    );
  });

  test('un message ordinaire ne répond à rien', () {
    expect(
      reponsesAuxBoutons(
        [
          message(moi, {'msgtype': 'm.text', 'body': 'Fusionner 3 et 10'})
        ],
        moi,
      ),
      isEmpty,
    );
  });
}
