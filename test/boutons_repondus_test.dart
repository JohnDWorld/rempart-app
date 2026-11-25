import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:rempart_app/presentation/widgets/chat/message_bubble.dart';

/// Base factice : le client n'y touche pas pour ce qu'on vérifie ici.
class _BaseFactice implements DatabaseApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final room = Room(
    id: '!sindri:rempart.test',
    client: Client('test', database: _BaseFactice()),
  );

  final question = Event(
    type: EventTypes.Message,
    content: {
      'msgtype': 'm.text',
      'body': 'Je fusionne les leçons 3 et 10 ?',
      'fr.rempart.boutons': [
        {'texte': 'Fusionner 3 et 10', 'valeur': '!fusion 3 10'},
        {'texte': 'Garder', 'valeur': '!garder'},
      ],
    },
    room: room,
    eventId: r'$question',
    senderId: '@sindri:rempart.test',
    originServerTs: DateTime(2026, 11, 25),
  );

  Future<void> afficher(WidgetTester t, {String? reponse}) => t.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: MessageBubble(
                event: question,
                isMine: false,
                onBouton: (texte, valeur) {},
                reponseBouton: reponse,
              ),
            ),
          ),
        ),
      );

  testWidgets('une question ouverte montre ses boutons', (t) async {
    await afficher(t);
    expect(find.text('Fusionner 3 et 10'), findsOneWidget);
    expect(find.text('Garder'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNothing);
  });

  testWidgets('répondue, elle ne montre plus que le choix', (t) async {
    await afficher(t, reponse: 'Fusionner 3 et 10');
    expect(find.text('Garder'), findsNothing);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    // Le libellé reste, en retrait : plus rien à toucher.
    expect(find.text('Fusionner 3 et 10'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Fusionner 3 et 10'),
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );
  });
}
