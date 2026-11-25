import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/app/theme.dart';
import 'package:rempart_app/presentation/widgets/chat/message_input.dart';

/// Le texte de la barre est tenu par l'écran de conversation, qui en fait la
/// légende d'une pièce jointe puis vide la barre. Avant le 2026-11-25, il
/// vivait dans la barre seule : l'image partait sans lui, et il restait à
/// envoyer à part.
void main() {
  Future<void> poser(WidgetTester t, TextEditingController saisie) =>
      t.pumpWidget(
        MaterialApp(
          theme: RempartTheme.light,
          home: Scaffold(
            body: Column(
              children: [
                const Expanded(child: SizedBox()),
                MessageInput(onSend: (_) {}, controleur: saisie),
              ],
            ),
          ),
        ),
      );

  testWidgets("ce qu'on tape se lit depuis l'écran", (t) async {
    final saisie = TextEditingController();
    addTearDown(saisie.dispose);
    await poser(t, saisie);
    await t.enterText(find.byType(TextField), 'Regarde cette photo');
    expect(saisie.text, 'Regarde cette photo');
  });

  testWidgets("vidée par l'écran, la barre repasse au micro", (t) async {
    final saisie = TextEditingController();
    addTearDown(saisie.dispose);
    await poser(t, saisie);
    await t.enterText(find.byType(TextField), 'Regarde cette photo');
    await t.pumpAndSettle();
    expect(find.byTooltip('Envoyer'), findsOneWidget);

    saisie.clear();
    await t.pumpAndSettle();
    expect(find.byTooltip('Envoyer'), findsNothing);
    expect(find.byTooltip('Message vocal'), findsOneWidget);
  });

  testWidgets("la barre qui disparaît laisse le texte à l'écran", (t) async {
    // La barre est retirée pendant une recherche : le texte doit l'attendre.
    final saisie = TextEditingController(text: 'Brouillon');
    addTearDown(saisie.dispose);
    await poser(t, saisie);
    expect(find.byTooltip('Envoyer'), findsOneWidget);

    await t.pumpWidget(const SizedBox());
    saisie.text = 'Toujours là';
    expect(saisie.text, 'Toujours là');
  });
}
