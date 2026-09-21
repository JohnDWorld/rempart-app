import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/app/theme.dart';

/// Lisibilité des textes d'état : « chiffré », « vérifié », « actif ».
///
/// Le badge de chiffrement, le signal de confiance de l'application, tombait
/// à 3,2:1 en thème sombre, parce que chaque écran piochait son propre vert
/// dans `Colors`. Ces mesures échouent si une teinte change sans que son
/// contraste suive.
void main() {
  double contraste(Color a, Color b) {
    double canal(double c) =>
        c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4) as double;
    double luminance(Color c) =>
        0.2126 * canal(c.r) + 0.7152 * canal(c.g) + 0.0722 * canal(c.b);
    final la = luminance(a);
    final lb = luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  /// Seuil WCAG AA pour un petit texte.
  const seuil = 4.5;

  final themes = {
    Brightness.light: (
      fond: RempartTokens.fondClair,
      surface: RempartTokens.surfaceClaire,
    ),
    Brightness.dark: (
      fond: RempartTokens.fondSombre,
      surface: RempartTokens.surfaceSombre,
    ),
  };

  for (final MapEntry(key: luminosite, value: t) in themes.entries) {
    final nom = luminosite == Brightness.dark ? 'sombre' : 'clair';

    test('badge « chiffré » lisible sur son fond teinté ($nom)', () {
      final texte = RempartTokens.texteSucces(luminosite);
      // Le fond du badge est la teinte du texte à 10 %, posée sur la page.
      final fondBadge = Color.alphaBlend(texte.withValues(alpha: 0.10), t.fond);
      expect(contraste(texte, fondBadge), greaterThanOrEqualTo(seuil));
    });

    test('badge « Non chiffré » lisible sur sa teinte ($nom)', () {
      // Le cas qui avait échappé au premier audit : un texte d'état posé sur
      // sa propre teinte perd du contraste, et l'orange qui tenait à nu
      // tombait à 4,10:1 sur la sienne.
      final texte = RempartTokens.texteAlerte(luminosite);
      for (final fond in [t.fond, t.surface]) {
        final fondBadge = Color.alphaBlend(texte.withValues(alpha: 0.12), fond);
        expect(contraste(texte, fondBadge), greaterThanOrEqualTo(seuil));
      }
    });

    test("textes de succès et d'alerte lisibles ($nom)", () {
      for (final fond in [t.fond, t.surface]) {
        expect(
          contraste(RempartTokens.texteSucces(luminosite), fond),
          greaterThanOrEqualTo(seuil),
        );
        expect(
          contraste(RempartTokens.texteAlerte(luminosite), fond),
          greaterThanOrEqualTo(seuil),
        );
      }
    });
  }

  // Le rouge des actions qui détruisent (« Supprimer », « Bloquer »), et le
  // texte d'un bouton posé sur lui. En thème sombre, l'ancien rouge unique ne
  // tenait que 3,49:1.
  for (final (nom, theme) in [
    ('clair', RempartTheme.light),
    ('sombre', RempartTheme.dark),
  ]) {
    test("rouge d'erreur lisible, et texte lisible dessus ($nom)", () {
      final c = theme.colorScheme;
      expect(contraste(c.error, c.surface), greaterThanOrEqualTo(seuil));
      expect(contraste(c.onError, c.error), greaterThanOrEqualTo(seuil));
    });
  }

  test("l'ancien orange du badge des bots échouait bien en clair", () {
    final fondBadge = Color.alphaBlend(
      Colors.orange.withValues(alpha: 0.12),
      RempartTokens.surfaceClaire,
    );
    expect(contraste(Colors.orange, fondBadge), lessThan(seuil));
  });

  test("l'ancien vert du badge échouait bien en sombre", () {
    // Témoin : sans lui, rien ne prouve que le test sait voir la panne.
    final ancien = Colors.green.shade800;
    final fondBadge = Color.alphaBlend(
      Colors.green.withValues(alpha: 0.10),
      RempartTokens.fondSombre,
    );
    expect(contraste(ancien, fondBadge), lessThan(seuil));
  });
  for (final luminosite in [Brightness.light, Brightness.dark]) {
    final nom = luminosite == Brightness.dark ? 'sombre' : 'clair';
    final couleurs =
        (luminosite == Brightness.dark ? RempartTheme.dark : RempartTheme.light)
            .colorScheme;
    final barre =
        (luminosite == Brightness.dark ? RempartTheme.dark : RempartTheme.light)
            .progressIndicatorTheme;

    test('la barre de progression distingue le fait du restant ($nom)', () {
      // Seuil WCAG 1.4.11 : un élément graphique porteur d'information se
      // distingue à 3:1. Ici l'information EST la frontière entre les deux
      // moitiés. La piste suivait `secondaryContainer`, un bleu ciel vif :
      // 1,86:1 en clair et 1,09:1 en sombre, où l'on ne voyait plus rien.
      expect(
        contraste(barre.color!, barre.linearTrackColor!),
        greaterThanOrEqualTo(3),
        reason: 'remplissage ${barre.color}, piste ${barre.linearTrackColor}',
      );
    });

    test('la piste reste visible sur sa surface ($nom)', () {
      // L'inverse du défaut corrigé : une piste si sourde qu'elle disparaît
      // laisse croire que la barre s'arrête là où le téléchargement en est.
      expect(
        contraste(barre.linearTrackColor!, couleurs.surface),
        greaterThan(1.3),
      );
    });

    test('la pastille « Rempart » des agents livrés est lisible ($nom)', () {
      // `secondaryContainer` retombait sur `secondary`, un bleu ciel vif, et
      // son texte sur du blanc : 2,77:1.
      expect(
        contraste(couleurs.onSecondaryContainer, couleurs.secondaryContainer),
        greaterThanOrEqualTo(seuil),
      );
    });
  }

  test('le bleu ciel vif en piste échouait bien, dans les deux thèmes', () {
    // Témoin : l'ancienne piste, celle que Flutter déduisait faute de
    // `secondaryContainer` déclaré.
    for (final remplissage in [RempartTokens.bleu, RempartTokens.bleuClair]) {
      expect(contraste(RempartTheme.secondaryColor, remplissage), lessThan(3));
    }
  });
}
