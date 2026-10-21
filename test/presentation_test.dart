import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/presentation/screens/bots/bots_hub_screen.dart';
import 'package:rempart_app/presentation/screens/presentation_screen.dart';

/// La présentation de Rempart, et le menu Bots où elle mène.
///
/// Son but compte autant que son contenu : chacun doit finir dans le menu
/// Bots et y voir la Boutique à agents, qu'il lise les trois écrans ou passe.
void main() {
  Future<void> ouvrir(WidgetTester tester, VoidCallback surFin) =>
      tester.pumpWidget(MaterialApp(home: PresentationScreen(surFin: surFin)));

  testWidgets('les trois écrans, puis la suite', (tester) async {
    var fini = false;
    await ouvrir(tester, () => fini = true);
    expect(find.text('Bienvenue sur Rempart'), findsOneWidget);

    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    expect(find.text('Retrouvez vos proches'), findsOneWidget);

    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    expect(find.text('Des agents à votre service'), findsOneWidget);
    // Sur le dernier écran, plus rien à passer : son bouton mène au même
    // endroit.
    expect(find.text('Passer').hitTestable(), findsNothing);

    expect(fini, isFalse);
    await tester.tap(find.text('Découvrir les agents'));
    expect(fini, isTrue);
  });

  testWidgets('« Passer » mène aussi au menu Bots', (tester) async {
    var fini = false;
    await ouvrir(tester, () => fini = true);
    await tester.tap(find.text('Passer'));
    expect(fini, isTrue);
  });

  testWidgets('le menu Bots ne met la Boutique en avant qu’en découverte',
      (tester) async {
    const phrase = 'Vos bots et vos agents sont ici. Vous retrouverez ce menu '
        'à tout moment depuis Nouveau message › Parler à un bot.';

    await tester.pumpWidget(const MaterialApp(home: BotsHubScreen()));
    expect(find.text(phrase), findsNothing);
    expect(find.text('Boutique à agents'), findsOneWidget);

    await tester
        .pumpWidget(const MaterialApp(home: BotsHubScreen(decouverte: true)));
    expect(find.text(phrase), findsOneWidget);
    expect(find.text('Boutique à agents'), findsOneWidget);
  });
}
