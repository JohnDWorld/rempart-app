import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:rempart_app/data/models/matrix_extensions.dart';

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

  Event video(Map<String, Object?> contenu) => Event(
        type: EventTypes.Message,
        content: {
          'msgtype': MessageTypes.Video,
          'info': {'mimetype': 'video/mp4', 'size': 1024},
          ...contenu,
        },
        room: room,
        eventId: r'$v',
        senderId: '@elle:rempart.test',
        originServerTs: DateTime(2026, 9, 30),
      );

  test('avec une légende, le nom reste celui du fichier', () {
    final e =
        video({'body': 'Gros câlin maman loulou', 'filename': 'VID_01.mp4'});
    expect(e.fileInfo!.fileName, 'VID_01.mp4');
  });

  test('sans légende, le corps est le nom du fichier', () {
    expect(video({'body': 'VID_02.mp4'}).fileInfo!.fileName, 'VID_02.mp4');
  });
}
