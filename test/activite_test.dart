import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:rempart_app/core/utils/activite.dart';
import 'package:rempart_app/presentation/widgets/chat/indicateur_activite.dart';

void main() {
  final maintenant = DateTime(2026, 11, 24, 12);
  const salon = '!salon:serveur';

  ToDeviceEvent signal({
    String sender = '@lea:serveur',
    String type = typeSignalEnregistrement,
    String room = salon,
    bool actif = true,
    Duration age = Duration.zero,
  }) =>
      ToDeviceEvent(
        sender: sender,
        type: type,
        content: contenuSignalEnregistrement(
          room,
          actif: actif,
          maintenant: maintenant.subtract(age),
        ),
      );

  bool? etat(ToDeviceEvent e) => etatSignalEnregistrement(
        e,
        roomId: salon,
        moi: '@moi:serveur',
        maintenant: maintenant,
      );

  group('signal « enregistre un vocal »', () {
    test('début et fin se lisent', () {
      expect(etat(signal()), isTrue);
      expect(etat(signal(actif: false)), isFalse);
    });

    test('un autre salon, un autre type ou soi-même ne comptent pas', () {
      expect(etat(signal(room: '!autre:serveur')), isNull);
      expect(etat(signal(type: 'm.dummy')), isNull);
      expect(etat(signal(sender: '@moi:serveur')), isNull);
    });

    test('un signal rejoué en retard est écarté', () {
      expect(etat(signal(age: const Duration(seconds: 20))), isTrue);
      expect(etat(signal(age: const Duration(minutes: 5))), isNull);
    });

    test('un contenu mal formé est écarté sans lever', () {
      final e = ToDeviceEvent(
        sender: '@lea:serveur',
        type: typeSignalEnregistrement,
        content: {'room_id': salon, 'actif': 'oui'},
      );
      expect(etat(e), isNull);
    });
  });

  group('libellé de l’en-tête', () {
    test('en tête-à-tête, personne n’est nommé', () {
      expect(
        libelleActivite(direct: true, noms: ['Léa'], enregistre: false),
        "en train d'écrire...",
      );
      expect(
        libelleActivite(direct: true, noms: ['Léa'], enregistre: true),
        'enregistre un vocal...',
      );
    });

    test('dans un groupe, les noms puis le nombre', () {
      expect(
        libelleActivite(direct: false, noms: ['Léa'], enregistre: true),
        'Léa enregistre un vocal...',
      );
      expect(
        libelleActivite(
            direct: false, noms: ['Léa', 'Inès'], enregistre: false),
        'Léa et Inès écrivent...',
      );
      expect(
        libelleActivite(direct: false, noms: ['a', 'b', 'c'], enregistre: true),
        'plusieurs personnes enregistrent un vocal...',
      );
    });
  });

  group('bulle animée', () {
    Widget bulle({required bool enregistre, required bool reduit}) =>
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduit),
            child: Scaffold(
              body: IndicateurActivite(
                enregistre: enregistre,
                libelle: 'Léa écrit...',
              ),
            ),
          ),
        );

    testWidgets('un micro pendant un vocal, des points sinon', (t) async {
      await t.pumpWidget(bulle(enregistre: true, reduit: false));
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      await t.pumpWidget(bulle(enregistre: false, reduit: false));
      expect(find.byIcon(Icons.mic_rounded), findsNothing);
      expect(find.bySemanticsLabel('Léa écrit...'), findsOneWidget);
    });

    testWidgets('mouvement réduit : plus rien ne bouge', (t) async {
      await t.pumpWidget(bulle(enregistre: true, reduit: true));
      // Une animation qui tourne encore ferait échouer l'attente.
      await t.pumpAndSettle();
      expect(t.hasRunningAnimations, isFalse);
    });
  });
}
