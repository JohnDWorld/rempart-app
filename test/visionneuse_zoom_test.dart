import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:rempart_app/data/services/cache_medias.dart';
import 'package:rempart_app/presentation/widgets/chat/visionneuse_image.dart';

/// Base factice : la visionneuse ne lit que des images déjà en mémoire.
class _BaseFactice implements DatabaseApi {
  @override
  Future<User?> getUser(String userId, Room room) async => null;

  @override
  Future<CachedProfileInformation?> getUserProfile(String userId) async =>
      null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Le zoom de la visionneuse, qui vit dans un défilement de pages.
///
/// En écartant deux doigts, le premier qui glissait de quelques pixels était
/// pris pour un changement de page, avant que le second ne se pose : la photo
/// filait vers sa voisine au lieu de s'agrandir (relevé le 2026-10-20).
void main() {
  final room = Room(
    id: '!r:rempart.test',
    client: Client('test', database: _BaseFactice()),
  );
  Event photo(String id) => Event(
        type: EventTypes.Message,
        content: {'msgtype': MessageTypes.Image, 'body': 'photo.png'},
        room: room,
        eventId: id,
        senderId: '@elle:rempart.test',
        originServerTs: DateTime(2026, 10, 20),
      );
  final photos = [photo(r'$a'), photo(r'$b'), photo(r'$c')];
  // Un pixel transparent : l'image n'a pas à se dessiner, seulement à exister.
  final pixel = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAj'
    'CB0C8AAAAASUVORK5CYII=',
  );

  setUpAll(() async {
    for (final p in photos) {
      await CacheMedias.instance
          .obtenir(cleMedia(p), () async => MediaCharge(pixel, 1));
    }
  });

  Future<void> ouvrirAuMilieu(WidgetTester tester) => tester.pumpWidget(
        MaterialApp(
          home: VisionneuseImage(
            images: photos,
            depart: 1,
            onEnregistrer: (_) {},
            onPartager: (_) {},
          ),
        ),
      );

  final image = find.byType(InteractiveViewer);
  double echelle(WidgetTester tester) => tester
      .widget<InteractiveViewer>(image)
      .transformationController!
      .value
      .getMaxScaleOnAxis();

  testWidgets('écarter deux doigts agrandit, sans changer de photo',
      (tester) async {
    await ouvrirAuMilieu(tester);
    final centre = tester.getCenter(image);

    // Comme une vraie main : le second doigt se pose un peu après le premier.
    final premier =
        await tester.startGesture(centre - const Offset(30, 0), pointer: 1);
    await tester.pump(const Duration(milliseconds: 20));
    final second =
        await tester.startGesture(centre + const Offset(30, 0), pointer: 2);
    await tester.pump();
    // Le pouce reste, l'index s'écarte : c'est ce mouvement-là, d'un seul
    // côté, que le défilement prenait pour un glissement.
    for (var i = 0; i < 10; i++) {
      await second.moveBy(const Offset(15, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await premier.up();
    await second.up();
    await tester.pumpAndSettle();

    expect(find.text('2 sur 3'), findsOneWidget);
    expect(echelle(tester), greaterThan(1.5));
  });

  testWidgets('un double appui agrandit, un second rend la taille',
      (tester) async {
    await ouvrirAuMilieu(tester);
    final centre = tester.getCenter(image);

    Future<void> doubleAppui() async {
      await tester.tapAt(centre);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(centre);
      await tester.pumpAndSettle();
    }

    await doubleAppui();
    expect(echelle(tester), greaterThan(1.5));

    // Agrandie, l'image se déplace sous le doigt au lieu de changer de page.
    await tester.dragFrom(centre, const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('2 sur 3'), findsOneWidget);

    await doubleAppui();
    expect(echelle(tester), closeTo(1, 0.01));
  });

  testWidgets("réduite, l'image glisse vers la suivante d'un doigt",
      (tester) async {
    await ouvrirAuMilieu(tester);
    await tester.fling(image, const Offset(-400, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('3 sur 3'), findsOneWidget);
  });
}
