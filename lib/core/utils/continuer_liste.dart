import 'package:flutter/services.dart';

/// Poursuit une liste à puces quand on passe à la ligne.
///
/// Écrire une liste dans une messagerie demandait de retaper le tiret à chaque
/// ligne. Ici, un passage à la ligne depuis « - sucrine » ouvre « - » tout
/// seul, et un second passage sur une puce restée vide l'efface au lieu
/// d'empiler des tirets orphelins.
///
/// Écrit comme un [TextInputFormatter] plutôt que branché sur une touche : le
/// clavier d'un téléphone n'envoie pas d'événement clavier exploitable, et la
/// règle devient ici une fonction du texte, donc vérifiable sans appareil.
class ContinuerListe extends TextInputFormatter {
  const ContinuerListe();

  /// Reconnaît « - », « * » ou « • », précédés d'une indentation éventuelle.
  ///
  /// Le tiret doit être suivi d'une espace : « -5 degrés » n'est pas une
  /// puce, et une ligne de séparation « --- » non plus.
  static final _puce = RegExp(r'^(\s*)([-*•])\s+');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue avant,
    TextEditingValue apres,
  ) {
    // Un seul caractère ajouté, et c'est un saut de ligne : tout le reste
    // (frappe ordinaire, collage, correction) passe sans être touché.
    if (apres.text.length != avant.text.length + 1) return apres;
    final curseur = apres.selection.baseOffset;
    if (curseur <= 0 || !apres.selection.isCollapsed) return apres;
    if (apres.text[curseur - 1] != '\n') return apres;

    // La ligne qu'on vient de quitter.
    final debutLigne = apres.text.lastIndexOf('\n', curseur - 2) + 1;
    final ligne = apres.text.substring(debutLigne, curseur - 1);
    final marque = _puce.firstMatch(ligne);
    if (marque == null) return apres;

    // Une puce restée vide : le second passage à la ligne l'efface et laisse
    // le curseur là, au lieu d'ouvrir une troisième puce que personne ne veut.
    if (ligne.trimRight() == marque.group(0)!.trimRight()) {
      final texte = apres.text.replaceRange(debutLigne, curseur, '');
      return TextEditingValue(
        text: texte,
        selection: TextSelection.collapsed(offset: debutLigne),
      );
    }

    // Sinon, on ouvre la puce suivante, indentation comprise.
    final prefixe = '${marque.group(1)}${marque.group(2)} ';
    final texte = apres.text.replaceRange(curseur, curseur, prefixe);
    return TextEditingValue(
      text: texte,
      selection: TextSelection.collapsed(offset: curseur + prefixe.length),
    );
  }
}
