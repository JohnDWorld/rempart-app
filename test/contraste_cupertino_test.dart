import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/app/cupertino_theme.dart';

/// Le texte posé sur l'accent iOS (bouton plein, par exemple) doit rester
/// lisible dans les deux thèmes. Il était blanc partout, or l'accent
/// s'éclaircit en sombre : « Enregistrer » tombait à 2,5:1 sur iPhone.
double _contraste(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final (claire, sombre) = la > lb ? (la, lb) : (lb, la);
  return (claire + 0.05) / (sombre + 0.05);
}

void main() {
  for (final (nom, theme) in [
    ('clair', RempartCupertinoTheme.light),
    ('sombre', RempartCupertinoTheme.dark),
  ]) {
    test('texte sur accent lisible en thème $nom', () {
      expect(
        _contraste(theme.primaryColor, theme.primaryContrastingColor),
        greaterThanOrEqualTo(4.5),
      );
    });
  }
}
