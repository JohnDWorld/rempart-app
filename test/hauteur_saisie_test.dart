import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/app/theme.dart';
import 'package:rempart_app/presentation/widgets/chat/message_input.dart';

/// La hauteur de la barre de saisie, mesurée plutôt que jugée à l'oeil.
///
/// Elle portait 23 points de vide au-dessus de la première ligne, bien
/// visibles dès qu'un message dépassait deux lignes : 8 de marge intérieure et
/// 15 de creux dans le champ. Aucun des deux ne servait, la hauteur d'une
/// ligne venant des boutons (48 points) et non du champ.
///
/// Les bornes sont larges à dessein : ce test empêche la dérive, il ne fige
/// pas un pixel. L'alignement, lui, est tenu par
/// `barre_saisie_alignement_test`, et les deux se lisent ensemble : gagner de
/// la hauteur en décalant le texte serait un mauvais échange.
void main() {
  Future<void> poser(WidgetTester tester, String texte) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: RempartTheme.light,
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox()),
              MessageInput(onSend: (_) {}, onAttachmentPressed: () {}),
            ],
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), texte);
    await tester.pump();
  }

  testWidgets('une ligne tient dans 56 points', (tester) async {
    await poser(tester, 'Bonjour');
    expect(tester.getSize(find.byType(ClipRRect).first).height, lessThan(57));
  });

  testWidgets('le vide au-dessus du texte reste sous 18 points',
      (tester) async {
    await poser(
      tester,
      'Un message assez long pour passer a la ligne plusieurs fois et remplir '
      'la hauteur maximale du champ de saisie, comme une vraie question.',
    );
    final capsule = tester.getRect(find.byType(ClipRRect).first);
    final texte = tester.getRect(find.byType(EditableText));
    expect(
      texte.top - capsule.top,
      lessThan(18),
      reason: 'vide de ${texte.top - capsule.top} points au-dessus du texte',
    );
  });
}
