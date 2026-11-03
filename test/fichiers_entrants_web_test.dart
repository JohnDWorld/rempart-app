@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/core/fichiers_entrants.dart';
import 'package:web/web.dart' as web;

// Dans un vrai navigateur : `flutter test --platform chrome <ce fichier>`.
// Les événements sont ceux qu'émet le navigateur, à ceci près qu'ils sont
// fabriqués ici (une page ne peut ni lire le presse-papier ni simuler un
// glisser venu du système).

web.DataTransfer _avecFichiers(Map<String, String> fichiers) {
  final transfert = web.DataTransfer();
  fichiers.forEach((nom, mime) {
    transfert.items.add(
      web.File(
        [Uint8List.fromList(nom.codeUnits).toJS].toJS,
        nom,
        web.FilePropertyBag(type: mime),
      ),
    );
  });
  return transfert;
}

void main() {
  late List<Future<List<FichierEntrant>>> recus;
  late List<bool> survols;
  late void Function() arreter;

  setUp(() {
    recus = [];
    survols = [];
    arreter = ecouterFichiersEntrants(
      surFichiers: recus.add,
      surSurvol: ({required actif}) => survols.add(actif),
    );
  });

  tearDown(() => arreter());

  test('une image collée est interceptée, nom et octets compris', () async {
    final evenement = web.ClipboardEvent(
      'paste',
      web.ClipboardEventInit(
        clipboardData: _avecFichiers({'image.png': 'image/png'}),
        cancelable: true,
      ),
    );
    web.document.dispatchEvent(evenement);

    expect(evenement.defaultPrevented, isTrue);
    final fichiers = await recus.single;
    expect(fichiers.single.nom, 'image.png');
    expect(fichiers.single.mime, 'image/png');
    expect(fichiers.single.octets, 'image.png'.codeUnits);
  });

  test('un texte collé suit son chemin', () {
    final texte = web.DataTransfer()..setData('text/plain', 'bonjour');
    final evenement = web.ClipboardEvent(
      'paste',
      web.ClipboardEventInit(clipboardData: texte, cancelable: true),
    );
    web.document.dispatchEvent(evenement);

    expect(evenement.defaultPrevented, isFalse);
    expect(recus, isEmpty);
  });

  test('plusieurs fichiers déposés arrivent ensemble, sans type inventé',
      () async {
    final transfert = _avecFichiers({
      'vacances.jpg': 'image/jpeg',
      'facture.pdf': 'application/pdf',
      'notes.inconnu': '',
    });
    final survol = web.DragEvent(
      'dragover',
      web.DragEventInit(dataTransfer: transfert, cancelable: true),
    );
    web.document.dispatchEvent(survol);
    expect(survol.defaultPrevented, isTrue, reason: 'sinon, pas de dépôt');
    expect(survols, [true]);

    final depot = web.DragEvent(
      'drop',
      web.DragEventInit(dataTransfer: transfert, cancelable: true),
    );
    web.document.dispatchEvent(depot);
    expect(depot.defaultPrevented, isTrue, reason: 'sinon, Rempart est quitté');
    expect(survols, [true, false]);

    final fichiers = await recus.single;
    expect(
      fichiers.map((f) => (f.nom, f.mime)),
      [
        ('vacances.jpg', 'image/jpeg'),
        ('facture.pdf', 'application/pdf'),
        ('notes.inconnu', null),
      ],
    );
  });

  test('un glisser de texte dans la page est laissé tranquille', () {
    final texte = web.DataTransfer()..setData('text/plain', 'bonjour');
    final survol = web.DragEvent(
      'dragover',
      web.DragEventInit(dataTransfer: texte, cancelable: true),
    );
    web.document.dispatchEvent(survol);

    expect(survol.defaultPrevented, isFalse);
    expect(survols, isEmpty);
  });

  test("une fois arrêtée, l'écoute ne retient plus rien", () {
    arreter();
    final evenement = web.ClipboardEvent(
      'paste',
      web.ClipboardEventInit(
        clipboardData: _avecFichiers({'image.png': 'image/png'}),
        cancelable: true,
      ),
    );
    web.document.dispatchEvent(evenement);

    expect(evenement.defaultPrevented, isFalse);
    expect(recus, isEmpty);
    arreter = () {};
  });
}
