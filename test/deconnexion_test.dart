import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/core/utils/deconnexion.dart';

void main() {
  test('une déconnexion qui aboutit ne fait rien de plus', () async {
    final faits = <String>[];
    await deconnecterSansSeBloquer(
      deconnexionSdk: () async => faits.add('sdk'),
      fermerSurLeServeur: () async => faits.add('serveur'),
      effacerLocal: () async => faits.add('local'),
    );
    expect(faits, ['sdk']);
  });

  test('un SDK bloqué ne bloque pas la déconnexion', () async {
    final faits = <String>[];
    await deconnecterSansSeBloquer(
      // Ce que fait le SDK 7.4.0 sur le web quand l'envoi des clés est figé.
      deconnexionSdk: () => Completer<void>().future,
      fermerSurLeServeur: () async => faits.add('serveur'),
      effacerLocal: () async => faits.add('local'),
      delai: const Duration(milliseconds: 10),
    );
    expect(faits, ['serveur', 'local']);
  });

  test('les données locales partent même si le serveur ne répond pas',
      () async {
    final faits = <String>[];
    await expectLater(
      deconnecterSansSeBloquer(
        deconnexionSdk: () => Completer<void>().future,
        fermerSurLeServeur: () async => throw Exception('hors ligne'),
        effacerLocal: () async => faits.add('local'),
        delai: const Duration(milliseconds: 10),
      ),
      throwsException,
    );
    expect(faits, ['local']);
  });
}
