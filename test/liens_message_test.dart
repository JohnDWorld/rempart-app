import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/presentation/widgets/chat/message_riche.dart';

/// Détection des adresses écrites en clair dans un message.
///
/// Une adresse mal découpée envoie l'utilisateur sur une page qui n'existe
/// pas, ou avale la ponctuation de la phrase.
void main() {
  final recognizers = <TapGestureRecognizer>[];
  TapGestureRecognizer faux(String href) {
    final r = TapGestureRecognizer();
    recognizers.add(r);
    return r;
  }

  tearDown(() {
    for (final r in recognizers) {
      r.dispose();
    }
    recognizers.clear();
  });

  List<InlineSpan> spans(String texte) => spansAvecLiens(
        texte: texte,
        style: const TextStyle(),
        couleurLien: Colors.blue,
        reconnaisseur: faux,
      );

  /// Les morceaux portant un geste : ce sont les liens.
  List<String> liens(String texte) => [
        for (final s in spans(texte))
          if (s is TextSpan && s.recognizer != null) s.text ?? '',
      ];

  test('un texte sans adresse reste un seul morceau', () {
    final r = spans('Bonjour, comment vas-tu ?');
    expect(r.length, 1);
    expect(liens('Bonjour, comment vas-tu ?'), isEmpty);
  });

  test('une adresse est isolée du reste', () {
    expect(
      liens('Source : https://exemple.fr/article ok'),
      ['https://exemple.fr/article'],
    );
  });

  test('le point final de la phrase n est pas avalé', () {
    // Sans cela, le lien mène à « …/article. », qui n'existe pas.
    expect(liens('Voir https://exemple.fr/article.'), ['https://exemple.fr/article']);
  });

  test('une parenthèse fermante est rendue à la phrase', () {
    expect(liens('(voir https://exemple.fr/a)'), ['https://exemple.fr/a']);
  });

  test('mais une parenthèse du lien lui reste', () {
    // Wikipédia écrit ainsi ses homonymies : la couper casse l'adresse.
    expect(
      liens('https://fr.wikipedia.org/wiki/Rempart_(fortification)'),
      ['https://fr.wikipedia.org/wiki/Rempart_(fortification)'],
    );
  });

  test('www sans schéma est reconnu et complété', () {
    final r = spans('www.exemple.fr');
    final lien = r.whereType<TextSpan>().firstWhere((s) => s.recognizer != null);
    expect(lien.text, 'www.exemple.fr');
  });

  test('plusieurs adresses dans un même message', () {
    expect(
      liens('a https://un.fr b https://deux.fr c'),
      ['https://un.fr', 'https://deux.fr'],
    );
  });

  test('le texte entier est conservé, sans perte ni doublon', () {
    const source = 'Source : https://exemple.fr/a. Merci !';
    final rendu = spans(source)
        .whereType<TextSpan>()
        .map((s) => s.text ?? '')
        .join();
    expect(rendu, source);
  });
}
