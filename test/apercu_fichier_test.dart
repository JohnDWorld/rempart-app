import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:rempart_app/data/services/apercu_pdf.dart';
import 'package:rempart_app/presentation/widgets/chat/apercu_fichier.dart';

class _BaseFactice implements DatabaseApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Le moteur PDF d'Android, remplacé : trois pages d'un pixel.
class _PdfFactice extends ApercuPdf {
  const _PdfFactice({this.abime = false});

  final bool abime;

  @override
  bool get disponible => true;

  @override
  Future<String> deposer(Uint8List octets) async => '/apercu/document.pdf';

  @override
  Future<void> effacer(String chemin) async {}

  @override
  Future<int> nombreDePages(String chemin) async =>
      abime ? throw Exception('protégé') : 3;

  @override
  Future<Uint8List> page(String chemin, int index, int largeur) async =>
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAj'
        'CB0C8AAAAASUVORK5CYII=',
      );
}

/// L'aperçu d'un fichier reçu. Un appui sur sa bulle ne faisait rien, et une
/// facture PDF envoyée par un agent ne pouvait aller que dans une autre
/// application (relevé le 2026-10-22).
void main() {
  final room = Room(
    id: '!r:rempart.test',
    client: Client('test', database: _BaseFactice()),
  );
  Event fichier(String nom, String mime) => Event(
        type: EventTypes.Message,
        content: {
          'msgtype': MessageTypes.File,
          'body': nom,
          'url': 'mxc://rempart.test/f',
          'info': {'mimetype': mime, 'size': 105392},
        },
        room: room,
        eventId: r'$f',
        senderId: '@fafnir:rempart.test',
        originServerTs: DateTime(2026, 10, 22),
      );

  Finder page(Pattern libelle) => find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            (w.properties.label?.startsWith(libelle) ?? false),
      );

  Future<List<Event>> ouvrir(
    WidgetTester tester,
    Event event, {
    ApercuPdf pdf = const _PdfFactice(),
  }) async {
    final enregistres = <Event>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ApercuFichier(
          event: event,
          onEnregistrer: enregistres.add,
          onPartager: (_) {},
          charger: (_) async => Uint8List(8),
          pdf: pdf,
        ),
      ),
    );
    // Pas `pumpAndSettle` : une page attend son image dans un cadre qui
    // tourne, et une image ne se décode jamais dans un test.
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    return enregistres;
  }

  testWidgets('un PDF s’affiche page par page', (tester) async {
    await ouvrir(tester, fichier('FA-OCT2026-024.pdf', 'application/pdf'));

    expect(find.text('FA-OCT2026-024.pdf'), findsOneWidget);
    expect(page('Page 1 sur 3'), findsOneWidget);
  });

  testWidgets('un PDF illisible retombe sur la fiche du fichier',
      (tester) async {
    await ouvrir(
      tester,
      fichier('facture.pdf', 'application/pdf'),
      pdf: const _PdfFactice(abime: true),
    );

    expect(find.textContaining('Aperçu impossible'), findsOneWidget);
    expect(page('Page '), findsNothing);
  });

  testWidgets('un autre fichier montre sa fiche, et s’enregistre',
      (tester) async {
    final evenement = fichier('archives.zip', 'application/zip');
    final enregistres = await ouvrir(tester, evenement);

    expect(find.text('archives.zip'), findsNWidgets(2));
    expect(page('Page '), findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Enregistrer'));
    expect(enregistres, [evenement]);
  });
}
