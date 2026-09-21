import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/presentation/widgets/chat/glisser_pour_repondre.dart';

/// Le glissement pour répondre.
///
/// Le seuil est ce qui distingue un geste voulu d'un doigt qui ripe en
/// faisant défiler le fil : trop bas, chaque défilement ouvrirait une
/// réponse.
void main() {
  Future<int> glisser(WidgetTester tester, double distance) async {
    var appels = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GlisserPourRepondre(
            onRepondre: () => appels++,
            child: const SizedBox(height: 60, width: 300, child: Text('salut')),
          ),
        ),
      ),
    );
    await tester.drag(find.text('salut'), Offset(distance, 0));
    await tester.pumpAndSettle();
    return appels;
  }

  testWidgets('un glissement franc déclenche la réponse', (tester) async {
    expect(await glisser(tester, 90), 1);
  });

  testWidgets('un frôlement ne déclenche rien', (tester) async {
    expect(await glisser(tester, 20), 0);
  });

  testWidgets('glisser vers la gauche ne déclenche rien', (tester) async {
    // La bulle de droite ne doit pas répondre à un geste inverse.
    expect(await glisser(tester, -90), 0);
  });

  testWidgets('le message revient à sa place après le geste', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GlisserPourRepondre(
            onRepondre: () {},
            child: const SizedBox(height: 60, width: 300, child: Text('salut')),
          ),
        ),
      ),
    );
    final depart = tester.getTopLeft(find.text('salut'));
    await tester.drag(find.text('salut'), const Offset(90, 0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('salut')), depart);
  });
}
