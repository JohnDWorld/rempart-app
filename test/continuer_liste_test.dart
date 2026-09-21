import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/core/utils/continuer_liste.dart';

/// La poursuite d'une liste à puces.
///
/// Le formateur touche à chaque frappe du champ de saisie : une règle trop
/// large abîmerait du texte ordinaire, ce qui se remarque bien plus qu'une
/// puce manquante.
void main() {
  const formateur = ContinuerListe();

  /// Simule la frappe d'un « Entrée » à la fin de [texte].
  TextEditingValue entree(String texte) {
    final avant = TextEditingValue(
      text: texte,
      selection: TextSelection.collapsed(offset: texte.length),
    );
    final apres = TextEditingValue(
      text: '$texte\n',
      selection: TextSelection.collapsed(offset: texte.length + 1),
    );
    return formateur.formatEditUpdate(avant, apres);
  }

  test('une puce en ouvre une autre', () {
    final r = entree('- sucrine');
    expect(r.text, '- sucrine\n- ');
    expect(r.selection.baseOffset, r.text.length);
  });

  test('la deuxième ligne suit aussi', () {
    expect(entree('- sucrine\n- pomme de terre').text,
        '- sucrine\n- pomme de terre\n- ');
  });

  test('une puce vide disparaît au lieu d en ouvrir une troisième', () {
    // Le « deux fois Entrée » : on sort de la liste sans laisser de tiret
    // orphelin, et sans descendre d'une ligne de plus.
    final r = entree('- sucrine\n- ');
    expect(r.text, '- sucrine\n');
    expect(r.selection.baseOffset, r.text.length);
  });

  test('l indentation est reprise', () {
    expect(entree('  - sous-point').text, '  - sous-point\n  - ');
  });

  test('les astérisques et les points médians marchent aussi', () {
    expect(entree('* un').text, '* un\n* ');
    expect(entree('• un').text, '• un\n• ');
  });

  test('du texte ordinaire reste intact', () {
    expect(entree('bonjour').text, 'bonjour\n');
  });

  test('un tiret sans espace n est pas une puce', () {
    // « -5 degrés ce matin » ne doit pas ouvrir de liste.
    expect(entree('-5 degrés').text, '-5 degrés\n');
  });

  test('une ligne de séparation n est pas une puce', () {
    expect(entree('---').text, '---\n');
  });

  test('un collage de plusieurs caractères passe sans être touché', () {
    const avant = TextEditingValue(
      text: '- un',
      selection: TextSelection.collapsed(offset: 4),
    );
    const colle = TextEditingValue(
      text: '- un\net deux',
      selection: TextSelection.collapsed(offset: 12),
    );
    expect(formateur.formatEditUpdate(avant, colle).text, '- un\net deux');
  });

  test('une frappe ordinaire n est pas modifiée', () {
    const avant = TextEditingValue(
      text: '- un',
      selection: TextSelection.collapsed(offset: 4),
    );
    const frappe = TextEditingValue(
      text: '- une',
      selection: TextSelection.collapsed(offset: 5),
    );
    expect(formateur.formatEditUpdate(avant, frappe).text, '- une');
  });
}
