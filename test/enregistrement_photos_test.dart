import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:rempart_app/data/services/enregistrement_photos.dart';

/// Base factice : le client n'y touche pas pour ce qu'on vérifie ici.
class _BaseFactice implements DatabaseApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const moi = '@moi:rempart.test';
  final activation = DateTime(2026, 9, 30, 12);
  final room = Room(
    id: '!salon:rempart.test',
    client: Client('test', database: _BaseFactice()),
  );

  Event message({
    String type = MessageTypes.Image,
    String auteur = '@elle:rempart.test',
    DateTime? le,
  }) =>
      Event(
        type: EventTypes.Message,
        content: {'msgtype': type, 'body': 'photo.jpg'},
        room: room,
        eventId: r'$e',
        senderId: auteur,
        originServerTs: le ?? activation.add(const Duration(minutes: 1)),
      );

  bool enregistree(Event e) => aEnregistrer(e, depuis: activation, moi: moi);

  test('une photo reçue après l activation part dans la galerie', () {
    expect(enregistree(message()), isTrue);
  });

  test('ni ses propres photos, ni celles d avant l activation', () {
    expect(enregistree(message(auteur: moi)), isFalse);
    expect(
      enregistree(message(le: activation.subtract(const Duration(days: 1)))),
      isFalse,
    );
  });

  test('ni les vidéos, ni les fichiers, ni le texte', () {
    expect(enregistree(message(type: MessageTypes.Video)), isFalse);
    expect(enregistree(message(type: MessageTypes.File)), isFalse);
    expect(enregistree(message(type: MessageTypes.Text)), isFalse);
  });
}
