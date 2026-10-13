import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/data/services/vocal_notification.dart';

void main() {
  const room = '!abc:rempart-messenger.fr';

  test('le nom ne garde que des caractères sûrs, et le format du son', () {
    final nom = nomFichierVocal(
      roomId: room,
      eventId: r'$Ab-c_9/x+y=:z',
      mime: 'audio/mp4',
    );
    expect(nom, matches(RegExp(r'^-?\d+_Ab-c_9xyz\.m4a$')));
    expect(
      nomFichierVocal(roomId: room, eventId: r'$e', mime: 'audio/ogg'),
      endsWith('.ogg'),
    );
  });

  test('les vocaux d une même conversation partagent leur préfixe', () {
    String prefixe(String roomId, String eventId) =>
        nomFichierVocal(roomId: roomId, eventId: eventId, mime: 'audio/mp4')
            .split('_')
            .first;
    expect(prefixe(room, r'$un'), prefixe(room, r'$deux'));
    expect(prefixe(room, r'$un'), isNot(prefixe('!autre:r', r'$un')));
  });
}
