import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/data/providers/taille_texte.dart';
import 'package:rempart_app/presentation/widgets/chat/message_riche.dart';

/// Taille du texte d'un message.
///
/// Le rendu riche n'impose aucune taille et prend celle qu'il hérite. C'est
/// exactement ce qui clochait : la bulle la posait sur un seul des deux
/// chemins, si bien qu'un message mis en forme sortait en 14 là où un message
/// brut sortait en 15,5. Ces mesures ancrent l'héritage, sans lequel le
/// réglage de l'utilisateur n'atteindrait que la moitié des messages.
void main() {
  /// Rend [html] sous un texte par défaut de [taille] et renvoie la taille
  /// effective du premier morceau de texte rendu.
  Future<double?> tailleRendue(
    WidgetTester tester,
    String html, {
    required double taille,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DefaultTextStyle.merge(
            style: TextStyle(fontSize: taille),
            child: MessageRiche(
              formattedBody: html,
              couleurTexte: Colors.black,
              surFondPropre: false,
            ),
          ),
        ),
      ),
    );
    final texte = tester.widget<RichText>(find.byType(RichText).first);
    return texte.text.style?.fontSize;
  }

  testWidgets('un message mis en forme suit la taille héritée', (tester) async {
    expect(await tailleRendue(tester, '<p>bonjour</p>', taille: 15.5), 15.5);
    expect(await tailleRendue(tester, '<p>bonjour</p>', taille: 20), 20);
  });

  testWidgets('le gras et les liens la suivent aussi', (tester) async {
    expect(
      await tailleRendue(
        tester,
        '<p>du <strong>gras</strong> et <a href="https://exemple.fr">un lien</a></p>',
        taille: 18,
      ),
      18,
    );
  });

  testWidgets('un bloc de code reste proportionnel', (tester) async {
    // Une taille fixe le laissait seul en arrière quand tout le reste
    // grossissait.
    final petit = await tailleRendue(tester, '<p><code>x</code></p>', taille: 14);
    final grand = await tailleRendue(tester, '<p><code>x</code></p>', taille: 28);
    expect(petit, isNotNull);
    expect(grand! / petit!, closeTo(2, 0.01));
  });

  test('les facteurs vont du plus petit au plus grand, autour de 1', () {
    // Le libellé promet un ordre : « Petite » doit réduire, « Normale » ne
    // rien changer, et la suite grossir.
    expect(TailleTexte.normale.facteur, 1);
    final facteurs = TailleTexte.values.map((t) => t.facteur).toList();
    expect(facteurs, orderedEquals(List.of(facteurs)..sort()));
    expect(TailleTexte.petite.facteur, lessThan(1));
    expect(TailleTexte.tresGrande.facteur, greaterThan(1));
  });
}
