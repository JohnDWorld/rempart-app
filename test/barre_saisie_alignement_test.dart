import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/app/theme.dart';
import 'package:rempart_app/presentation/widgets/chat/message_input.dart';

/// L'alignement de la barre de saisie, mesuré plutôt que jugé à l'oeil.
///
/// Les icônes se retrouvaient sous le texte parce que la rangée s'aligne sur
/// le bas (pour que les boutons restent en bas quand le message grandit) et
/// qu'une boîte plus courte que ses voisines y descend d'autant. Un écart de
/// quelques points se voit, et ne se devine pas dans le code.
void main() {
  Future<void> poser(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: RempartTheme.light,
        home: Scaffold(
          body: MessageInput(
            onSend: (_) {},
            onAttachmentPressed: () {},
          ),
        ),
      ),
    );
  }

  testWidgets('le trombone est centré sur la ligne de saisie', (tester) async {
    await poser(tester);
    final trombone = tester.getRect(find.byIcon(Icons.attach_file));
    final texte = tester.getRect(find.byType(EditableText));
    expect(
      (trombone.center.dy - texte.center.dy).abs(),
      lessThan(1),
      reason: 'trombone ${trombone.center.dy}, texte ${texte.center.dy}',
    );
  });

  testWidgets("le bouton d'envoi l'est aussi", (tester) async {
    await poser(tester);
    final micro = tester.getRect(find.byIcon(Icons.mic_none_rounded));
    final texte = tester.getRect(find.byType(EditableText));
    expect(
      (micro.center.dy - texte.center.dy).abs(),
      lessThan(1),
      reason: 'micro ${micro.center.dy}, texte ${texte.center.dy}',
    );
  });
}
