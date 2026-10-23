import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:rempart_app/data/models/matrix_extensions.dart';

class _BaseFactice implements DatabaseApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Un message dont cet appareil n'a pas la clé. Son corps est l'erreur du
/// SDK, en anglais, qui s'affichait telle quelle dans les bulles d'un
/// appareil neuf (relevé le 2026-10-23).
void main() {
  final room = Room(
    id: '!r:rempart.test',
    client: Client('test', database: _BaseFactice()),
  );
  Event evenement(Map<String, Object?> contenu,
          {String type = 'm.room.message'}) =>
      Event(
        type: type,
        content: contenu,
        room: room,
        eventId: r'$e',
        senderId: '@lea:rempart.test',
        originServerTs: DateTime(2026, 10, 23),
      );

  test('un message illisible se dit en français', () {
    final illisible = evenement(
      {
        'msgtype': MessageTypes.BadEncrypted,
        'body': 'The sender has not sent us the session key.',
        'can_request_session': true,
      },
      type: EventTypes.Encrypted,
    );
    expect(illisible.estIllisible, isTrue);
    expect(illisible.displayText, '🔒 Message illisible sur cet appareil');
    expect(illisible.texteApercu, isNot(contains('session key')));
  });

  test('un message lisible garde son texte', () {
    final lisible = evenement({'msgtype': MessageTypes.Text, 'body': 'Salut'});
    expect(lisible.estIllisible, isFalse);
    expect(lisible.displayText, 'Salut');
  });
}
