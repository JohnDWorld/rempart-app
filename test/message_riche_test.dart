import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/presentation/widgets/chat/message_riche.dart';

/// Le rendu du `formatted_body` reçoit du HTML produit par une gateway ou par
/// un autre client Matrix : il doit tenir sur des entrées imparfaites sans
/// jamais faire tomber le fil de discussion.
void main() {
  Future<void> afficher(WidgetTester tester, String html) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageRiche(
            formattedBody: html,
            couleurTexte: Colors.black,
            surFondPropre: false,
          ),
        ),
      ),
    );
  }

  testWidgets('rend les emphases sans afficher les balises', (tester) async {
    await afficher(
      tester,
      "<p>du <strong>gras</strong> et de l'<em>italique</em></p>",
    );

    expect(find.textContaining('gras'), findsOneWidget);
    expect(find.textContaining('<strong>'), findsNothing);
  });

  testWidgets('encadre un bloc de code et affiche son langage', (tester) async {
    await afficher(
      tester,
      '<pre><code class="language-python">print("salut")</code></pre>',
    );

    expect(find.text('python'), findsOneWidget);
    expect(find.text('print("salut")'), findsOneWidget);
    expect(find.byTooltip('Copier le code'), findsOneWidget);
  });

  testWidgets('un bloc de code sans langue reste rendu', (tester) async {
    await afficher(tester, '<pre><code>ls -la</code></pre>');

    expect(find.text('code'), findsOneWidget);
    expect(find.text('ls -la'), findsOneWidget);
  });

  testWidgets('retire la citation mx-reply, déjà dessinée par la bulle',
      (tester) async {
    await afficher(
      tester,
      '<mx-reply><blockquote>message cité</blockquote></mx-reply>'
      ' <p>ma réponse</p>',
    );

    expect(find.textContaining('ma réponse'), findsOneWidget);
    expect(find.textContaining('message cité'), findsNothing);
  });

  testWidgets('numérote une liste ordonnée', (tester) async {
    await afficher(tester, '<ol><li>un</li><li>deux</li></ol>');

    expect(find.text('1. '), findsOneWidget);
    expect(find.text('2. '), findsOneWidget);
  });

  testWidgets('encadre un bloc de code même piégé dans un paragraphe',
      (tester) async {
    // HTML mal formé, produit par un autre client Matrix ou par un agent qui
    // colle son bloc au texte. Sans traitement, le code se noyait dans le
    // paragraphe et perdait cadre, bouton copier et défilement.
    await afficher(
      tester,
      '<p>Voici :<pre><code class="language-sh">ls -la</code></pre></p>',
    );

    expect(find.text('sh'), findsOneWidget);
    expect(find.byTooltip('Copier le code'), findsOneWidget);
  });

  testWidgets('encadre une citation même en position en ligne', (tester) async {
    await afficher(tester, '<p>Il a dit <blockquote>bonjour</blockquote></p>');

    expect(find.textContaining('bonjour'), findsOneWidget);
  });

  testWidgets('ne casse pas sur du HTML vide ou inconnu', (tester) async {
    await afficher(tester, '');
    expect(tester.takeException(), isNull);

    await afficher(tester, '<inconnu><p>texte</p></inconnu>');
    expect(find.textContaining('texte'), findsOneWidget);
  });

  testWidgets('un lien porte un geste cliquable', (tester) async {
    // Le HTML est celui qu'un agent produit reellement : la gateway convertit
    // `[texte](url)` en `<a href>`, et le lien doit rester actionnable.
    await afficher(
      tester,
      '<p>Suivre la procedure : '
          '<a href="https://exemple.test/doc.pdf">ouvrir la procedure</a></p>',
    );

    // Parcours a la main : `visitChildren` n'appelle pas le visiteur sur un
    // span sans texte, or c'est precisement la distinction qui compte ici.
    bool porteUnGeste(InlineSpan span) {
      if (span is! TextSpan) return false;
      if (span.text != null && span.recognizer is TapGestureRecognizer) {
        return true;
      }
      for (final enfant in span.children ?? const <InlineSpan>[]) {
        if (porteUnGeste(enfant)) return true;
      }
      return false;
    }

    final cliquable = tester
        .widgetList<RichText>(find.byType(RichText))
        .any((rendu) => porteUnGeste(rendu.text));

    expect(find.textContaining('ouvrir la procedure'), findsOneWidget);
    expect(cliquable, isTrue,
        reason: 'le geste doit etre porte par un span qui contient du texte, '
            'sinon Flutter ne le declenchera jamais');
  });

  testWidgets('des sauts entre blocs ne creusent pas de blancs',
        (tester) async {
      // Ce que produit un agent qui sépare ses paragraphes deux fois : par
      // `<p>` et par `<br/>`. Rendus littéralement, ces sauts empilaient des
      // lignes vides et le message se lisait à travers des trous.
      await afficher(tester, '<p>Un.</p><br/><br/><p>Deux.</p><br/><p>Trois.</p>');
      final aere = tester.getSize(find.byType(MessageRiche)).height;

      await afficher(tester, '<p>Un.</p><p>Deux.</p><p>Trois.</p>');
      expect(
        aere,
        tester.getSize(find.byType(MessageRiche)).height,
        reason: 'les sauts entre blocs ne doivent rien ajouter',
      );
    });

    testWidgets('les sauts consecutifs dans un paragraphe sont reduits',
        (tester) async {
      await afficher(tester, 'Un.<br/><br/><br/>Deux.');
      final triple = tester.getSize(find.byType(MessageRiche)).height;

      await afficher(tester, 'Un.<br/>Deux.');
      expect(triple, tester.getSize(find.byType(MessageRiche)).height);
    });
}
