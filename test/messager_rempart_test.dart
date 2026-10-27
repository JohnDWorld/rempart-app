import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/presentation/widgets/common/messager_rempart.dart';

void main() {
  late BuildContext contexte;

  Future<void> monter(WidgetTester tester) => tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MessagerRempart(child: child!),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                contexte = context;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );

  void afficher(String texte) => ScaffoldMessenger.of(contexte)
      .showSnackBar(SnackBar(content: Text(texte)));

  testWidgets('un bandeau remplace le précédent au lieu de le suivre',
      (tester) async {
    await monter(tester);
    for (var i = 1; i <= 5; i++) {
      afficher('Supprimée $i');
    }
    // Quelques secondes, et non vingt : les quatre premiers ne passent pas.
    await tester.pumpAndSettle();
    expect(find.text('Supprimée 5'), findsOneWidget);
    for (var i = 1; i < 5; i++) {
      expect(find.text('Supprimée $i'), findsNothing);
    }
  });

  testWidgets('un appui ferme le bandeau', (tester) async {
    await monter(tester);
    afficher('Conversation supprimée');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conversation supprimée'));
    await tester.pumpAndSettle();
    expect(find.text('Conversation supprimée'), findsNothing);
  });

  group('sous CupertinoApp (iPhone)', () {
    Future<void> monterSousCupertino(
      WidgetTester tester,
      Widget Function(Widget) messager,
    ) =>
        tester.pumpWidget(
          CupertinoApp(
            builder: (context, child) => messager(child!),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  contexte = context;
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        );

    testWidgets(
        'MessagerRempart seul ne passe pas la vérification de Flutter : '
        "c'est le piège", (tester) async {
      await monterSousCupertino(tester, (c) => MessagerRempart(child: c));
      expect(() => afficher('Profil enregistré'), throwsFlutterError);
    });

    testWidgets('MessagerRempartCupertino affiche, remplace et ferme',
        (tester) async {
      await monterSousCupertino(
        tester,
        (c) => MessagerRempartCupertino(child: c),
      );
      afficher('Premier');
      afficher('Profil enregistré');
      await tester.pumpAndSettle();
      expect(find.text('Premier'), findsNothing);
      expect(find.text('Profil enregistré'), findsOneWidget);
      await tester.tap(find.text('Profil enregistré'));
      await tester.pumpAndSettle();
      expect(find.text('Profil enregistré'), findsNothing);
    });
  });
}
