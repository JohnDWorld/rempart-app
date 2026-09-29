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
}
