import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/app/theme.dart';

/// Lisibilité de la citation affichée au-dessus d'une réponse.
///
/// Elle a déjà été illisible deux fois, dont une invisible : le fond valait
/// `primary` par-dessus la bulle `primary`, soit un rapport de 1,00 avec elle.
/// Rien ne le signalait, puisque le code paraissait poser une teinte. D'où ces
/// mesures, qui échouent si une couleur change sans que l'autre suive.
void main() {
  /// Rapport de contraste WCAG 2.1 entre deux couleurs opaques.
  double contraste(Color a, Color b) {
    double canal(double c) =>
        c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4) as double;
    double luminance(Color c) =>
        0.2126 * canal(c.r) + 0.7152 * canal(c.g) + 0.0722 * canal(c.b);
    final la = luminance(a);
    final lb = luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  /// Aplatit une couleur translucide sur son fond : c'est ce que voit l'oeil,
  /// et mesurer l'alpha sans l'aplatir donnerait un résultat faux.
  Color aplatir(Color dessus, Color fond) =>
      Color.alphaBlend(dessus, fond.withAlpha(255));

  const clair = ColorScheme.light(
    primary: RempartTokens.bleu,
    onSurface: RempartTokens.texteClair,
  );
  const sombre = ColorScheme.dark(
    primary: RempartTokens.bleu,
    onPrimary: Colors.white,
    surface: RempartTokens.surfaceSombre,
    onSurface: RempartTokens.texteSombre,
  );

  /// Vérifie un contexte complet : fond détaché de la bulle, puis textes
  /// lisibles sur ce fond.
  void verifier(
    String contexte,
    CouleursCitation couleurs,
    Color bulle,
  ) {
    final fond = aplatir(couleurs.fond, bulle);

    // Le bloc doit se distinguer de la bulle qui le porte. Le seuil est bas :
    // une citation n'est pas un bouton, et la barre de gauche fait le gros du
    // travail. Mais 1,00 signifie « même couleur », donc rien du tout.
    expect(contraste(fond, bulle), greaterThan(1.15),
        reason: '$contexte : le fond de la citation se confond avec la bulle');

    // Seuil AA pour du texte de 12 points.
    expect(contraste(aplatir(couleurs.nom, fond), fond), greaterThanOrEqualTo(4.5),
        reason: "$contexte : nom de l'expéditeur illisible");
    expect(contraste(aplatir(couleurs.texte, fond), fond), greaterThanOrEqualTo(4.5),
        reason: '$contexte : texte cité illisible');
  }

  test('dans ma propre bulle', () {
    // Le cas qui avait regressé : fond primary sur bulle primary.
    verifier(
      'ma bulle',
      CouleursCitation.pour(
        estLaMienne: true,
        schema: clair,
        luminosite: Brightness.light,
      ),
      clair.primary,
    );
  });

  test('dans la bulle du contact, thème clair', () {
    verifier(
      'contact clair',
      CouleursCitation.pour(
        estLaMienne: false,
        schema: clair,
        luminosite: Brightness.light,
      ),
      RempartTokens.surfaceClaire,
    );
  });

  test('dans la bulle du contact, thème sombre', () {
    verifier(
      'contact sombre',
      CouleursCitation.pour(
        estLaMienne: false,
        schema: sombre,
        luminosite: Brightness.dark,
      ),
      RempartTokens.surfaceSombre,
    );
  });

  test('la barre de gauche se voit sur le fond de la citation', () {
    // C'est elle qui signale la citation avant même la nuance de fond : elle
    // doit tenir le seuil des elements graphiques (3,0).
    for (final cas in [
      (CouleursCitation.pour(estLaMienne: true, schema: clair, luminosite: Brightness.light), clair.primary),
      (CouleursCitation.pour(estLaMienne: false, schema: clair, luminosite: Brightness.light), RempartTokens.surfaceClaire),
      (CouleursCitation.pour(estLaMienne: false, schema: sombre, luminosite: Brightness.dark), RempartTokens.surfaceSombre),
    ]) {
      final fond = aplatir(cas.$1.fond, cas.$2);
      expect(contraste(aplatir(cas.$1.barre, fond), fond), greaterThanOrEqualTo(3.0));
    }
  });
}
