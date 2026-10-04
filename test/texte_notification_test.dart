import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:rempart_app/data/services/notification_service.dart';

/// Base factice : le client n'y touche pas pour ce qu'on vérifie ici.
class _BaseFactice implements DatabaseApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final room = Room(
    id: '!salon:rempart.test',
    client: Client('test', database: _BaseFactice()),
  );

  Event message(Map<String, Object?> contenu) => Event(
        type: EventTypes.Message,
        content: contenu,
        room: room,
        eventId: r'$m',
        senderId: '@elle:rempart.test',
        originServerTs: DateTime(2026, 10, 4),
      );

  test('un vocal s annonce « Message vocal », jamais par son nom de fichier', () {
    final vocal = message({
      'msgtype': MessageTypes.Audio,
      'body': 'vocal_1788625858562.m4a',
      'info': {'mimetype': 'audio/mp4', 'duration': 4000},
      'org.matrix.msc3245.voice': <String, Object?>{},
    });
    expect(NotificationService.texteDeNotification(vocal), 'Message vocal');
  });

  test('un texte reste le texte, un corps vide devient « Nouveau message »', () {
    expect(
      NotificationService.texteDeNotification(
        message({'msgtype': MessageTypes.Text, 'body': 'On se voit à 18 h ?'}),
      ),
      'On se voit à 18 h ?',
    );
    expect(
      NotificationService.texteDeNotification(
        message({'msgtype': MessageTypes.Text, 'body': '  '}),
      ),
      'Nouveau message',
    );
  });
}
