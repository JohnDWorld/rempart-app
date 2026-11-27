import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/app/theme.dart';
import 'package:rempart_app/data/providers/emoji_jaime.dart';
import 'package:rempart_app/presentation/widgets/chat/choix_emoji.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tous les emojis en réaction et en j'aime, comme sur WhatsApp ou Signal.
/// Avant le 2026-11-27, six symboles fixes en réaction et huit pour le
/// j'aime.
void main() {
  test('les emojis que la police dessine en noir ne sont pas proposés', () {
    for (final noir in ['↩️', '⬆️', '1️⃣', '#️⃣', '©️', '™️', '‼️', '▶️']) {
      expect(dessineEnNoir(noir), isTrue, reason: noir);
    }
    for (final couleur in ['👍', '👍🏽', '❤️', '💙', '⚡', '➡️', '✅', '❌']) {
      expect(dessineEnNoir(couleur), isFalse, reason: couleur);
    }
    final proposes = {
      for (final categorie in jeuEmojis(const Locale('fr')))
        for (final e in categorie.emoji) e.emoji.trim(),
    };
    expect(proposes, containsAll(['💙', '⚡', '👍', '😂']));
    expect(proposes, isNot(contains('↩️')));
  });

  test('la recherche trouve par un mot seul, avec ou sans accent', () {
    final cles = motsCles('amour | cœur | cœur bleu | sentiment').split(' | ');
    expect(cles, containsAll(['bleu', 'coeur', 'cœur', 'coeur bleu']));
    final eclair = motsCles('courant | éclair | haute tension').split(' | ');
    expect(eclair, containsAll(['eclair', 'éclair', 'haute', 'tension']));
    final bleus = [
      for (final categorie in jeuEmojis(const Locale('fr')))
        for (final e in categorie.emoji)
          if (e.keywords.any((k) => k.startsWith('bleu'))) e.emoji,
    ];
    expect(bleus, contains('💙'));
  });

  test("le j'aime prend tout emoji sauf ❌, déjà le pouce en bas", () {
    expect(emojiJaimeAccepte('💙'), isTrue);
    expect(emojiJaimeAccepte('⚡'), isTrue);
    expect(emojiJaimeAccepte('❌'), isFalse);
    expect(emojiJaimeAccepte(' '), isFalse);
    expect(emojiJaimeAccepte(null), isFalse);
  });

  testWidgets("rend l'emoji touché", (t) async {
    SharedPreferences.setMockInitialValues({});
    String? choisi;
    await t.pumpWidget(
      MaterialApp(
        theme: RempartTheme.light,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChoixEmoji(onChoisi: (emoji) => choisi = emoji),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Aucun emoji récent'), findsOneWidget);

    await t.tap(find.byIcon(Icons.tag_faces));
    await t.pumpAndSettle();
    await t.tap(find.text('😂'));
    expect(choisi, '😂');
  });
}
