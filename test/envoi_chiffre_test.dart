import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:rempart_app/data/services/client_rempart.dart';

/// Base factice : le client n'y touche pas pour ce qu'on vérifie ici.
class _BaseFactice implements DatabaseApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late ClientRempart client;

  Room salon(String id, {required bool chiffre}) {
    final room = Room(id: id, client: client);
    if (chiffre) {
      room.setState(
        Event(
          type: EventTypes.Encryption,
          content: {'algorithm': Client.supportedGroupEncryptionAlgorithms.first},
          stateKey: '',
          room: room,
          eventId: r'$chiffrement',
          senderId: '@createur:rempart.test',
          originServerTs: DateTime(2026),
        ),
      );
    }
    client.rooms.add(room);
    return room;
  }

  setUp(() {
    client = ClientRempart('test', database: _BaseFactice());
  });

  group('un salon chiffré', () {
    test("refuse un message en clair, quelle qu'en soit la voie", () {
      salon('!chiffre:rempart.test', chiffre: true);
      // C'est exactement ce que le SDK envoie quand vodozemac n'a pas
      // démarré : le contenu tel quel, sous son type d'origine.
      expect(
        () => client.sendMessage(
          '!chiffre:rempart.test',
          EventTypes.Message,
          'txn1',
          {'msgtype': 'm.text', 'body': 'secret'},
        ),
        throwsA(isA<ChiffrementIndisponible>()),
      );
    });

    test('laisse passer le message chiffré et la réaction', () async {
      salon('!chiffre:rempart.test', chiffre: true);
      for (final type in [EventTypes.Encrypted, EventTypes.Reaction]) {
        // Le client n'a pas de serveur : l'appel échoue plus loin, mais PAS
        // sur le refus, ce qui prouve qu'il a été admis.
        await expectLater(
          client.sendMessage('!chiffre:rempart.test', type, 'txn-$type', {}),
          throwsA(isNot(isA<ChiffrementIndisponible>())),
        );
      }
    });
  });

  test("un salon non chiffré (robot sans clés) n'est pas concerné", () async {
    salon('!clair:rempart.test', chiffre: false);
    await expectLater(
      client.sendMessage('!clair:rempart.test', EventTypes.Message, 'txn2', {
        'msgtype': 'm.text',
        'body': '/start',
      }),
      throwsA(isNot(isA<ChiffrementIndisponible>())),
    );
  });

  test('le refus marque le message en échec sans boucler', () {
    // Le SDK ne réessaie pas une `MatrixException` : sans cet héritage, il
    // relancerait l'envoi chaque seconde pendant une minute.
    expect(ChiffrementIndisponible(), isA<MatrixException>());
    expect(
      ChiffrementIndisponible().toString(),
      contains("chiffrement n'est pas disponible"),
    );
  });

  test('règle : seuls le chiffré et la réaction passent en salon chiffré', () {
    expect(envoiAdmis(salonChiffre: true, type: EventTypes.Encrypted), isTrue);
    expect(envoiAdmis(salonChiffre: true, type: EventTypes.Reaction), isTrue);
    expect(envoiAdmis(salonChiffre: true, type: EventTypes.Message), isFalse);
    expect(envoiAdmis(salonChiffre: true, type: 'm.sticker'), isFalse);
    expect(envoiAdmis(salonChiffre: false, type: EventTypes.Message), isTrue);
  });
}
