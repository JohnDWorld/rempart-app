import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/presentation/screens/legal/document_legal.dart';
import 'package:rempart_app/presentation/screens/legal/politique_confidentialite_screen.dart';

/// La politique de confidentialité publiée sur le web dit exactement ce que
/// dit l'application.
///
/// Google Play exige une adresse web publique, et l'application a son propre
/// écran : deux copies d'un texte juridique finissent par diverger, et
/// l'utilisateur lirait alors deux engagements différents selon l'endroit.
/// L'écran de l'application fait foi ; la page se régénère à partir de lui.
void main() {
  /// Le texte visible de la page : balises retirées, entités décodées,
  /// espaces ramenés à un seul.
  String texteDeLaPage() {
    final brut = File(
      '../rempart-backend/web/politique-confidentialite.html',
    ).readAsStringSync();
    final corps = brut.substring(brut.indexOf('<main>'));
    // Les liens disparaissent sans laisser d'espace, sans quoi l'adresse
    // suivie d'un point deviendrait « proton.me . ». Les autres balises
    // séparent des blocs : elles valent une espace.
    return corps
        .replaceAll(RegExp('</?a[^>]*>'), '')
        .replaceAll(RegExp('<[^>]+>'), ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  String compacter(String texte) => texte.replaceAll(RegExp(r'\s+'), ' ');

  testWidgets("chaque paragraphe de l'application figure sur la page", (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: PolitiqueConfidentialiteScreen()),
    );
    final document = tester.widget<DocumentLegal>(find.byType(DocumentLegal));
    final page = texteDeLaPage();

    expect(page, contains(document.miseAJour));
    for (final section in document.sections) {
      expect(page, contains(section.titre), reason: 'titre absent');
      for (final paragraphe in section.paragraphes) {
        expect(
          page,
          contains(compacter(paragraphe)),
          reason: 'paragraphe absent ou modifié de « ${section.titre} »',
        );
      }
    }
  });
}
