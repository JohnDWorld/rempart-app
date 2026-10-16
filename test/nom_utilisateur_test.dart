import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/core/utils/nom_utilisateur.dart';

void main() {
  group('règles', () {
    // Les cas essayés sur la base (`nom_utilisateur_refuse`) le 2026-10-15 :
    // l'application doit accepter et refuser exactement les mêmes.
    const permis = {
      'marie': true,
      'marie.d': true,
      'jean.dupont42': true,
      'abbbbbbbbbbbbbbbbbbbbbbbbbbbbb': true, // 30 caractères
      'ab': false,
      'abbbbbbbbbbbbbbbbbbbbbbbbbbbbbb': false, // 31
      'marie..d': false,
      'marie_': false,
      '1marie': false,
      'marie-d': false,
      'léa': false,
      'rempart_x': false,
      'compta_bot': false,
      'admin': false,
      'u_abc': false,
    };
    for (final MapEntry(key: nom, value: attendu) in permis.entries) {
      test(nom, () {
        expect(problemeNomUtilisateur(nom) == null, attendu);
      });
    }

    test('le refus « pris » de la base a son propre message', () {
      expect(
        messageRefusNomUtilisateur('pris', 'marie'),
        'Ce nom est déjà pris',
      );
      expect(
        messageRefusNomUtilisateur('reserve', 'admin'),
        'Ce nom est réservé',
      );
    });
  });

  test('normalisation : minuscules, sans espace ni @ autour', () {
    expect(normaliserNomUtilisateur('  @Marie.D '), 'marie.d');
  });

  test('un nom tiré de l’adresse se reconnaît, casse comprise', () {
    expect(nomTireDeLAdresse('j.dupont40', 'J.Dupont40@exemple.fr'), isTrue);
    expect(nomTireDeLAdresse('jean.d', 'j.dupont40@exemple.fr'), isFalse);
  });

  group('suggestion', () {
    test('accents, espaces et apostrophes', () {
      expect(suggestionNomUtilisateur('Hélène Dupont'), 'helene.dupont');
      expect(suggestionNomUtilisateur("Zoé D'Arc"), 'zoe.d.arc');
    });

    test('toujours permise, ou vide', () {
      for (final nom in [
        '  Marie  ',
        '42 Jean',
        'Jean-Édouard de la Tour du Pin Verclause',
        '!!',
        'Œdipe',
      ]) {
        final suggestion = suggestionNomUtilisateur(nom);
        final tropCourte = suggestion.length < longueurMinNomUtilisateur;
        expect(
          tropCourte || problemeNomUtilisateur(suggestion) == null,
          isTrue,
          reason: '$nom -> $suggestion',
        );
      }
      expect(suggestionNomUtilisateur('42 Jean'), 'jean');
      expect(suggestionNomUtilisateur('!!'), '');
    });
  });

  group('liens de contact', () {
    test('aller et retour', () {
      final lien = lienContact('marie.d');
      expect(lien, 'https://app.rempart-messenger.fr/contact/marie.d');
      expect(nomDepuisLienContact(lien), 'marie.d');
    });

    test('un ancien nom tiré d’une adresse reste trouvable', () {
      expect(
        nomDepuisLienContact(
          'https://app.rempart-messenger.fr/contact/Jean-Dupont',
        ),
        'jean-dupont',
      );
    });

    test('rien d’autre n’est pris pour un contact', () {
      for (final texte in [
        'https://exemple.fr/contact/marie',
        'http://app.rempart-messenger.fr/contact/marie',
        'https://app.rempart-messenger.fr/contact/',
        'https://app.rempart-messenger.fr/contact/marie/plus',
        'https://app.rempart-messenger.fr/#/home',
        '{"appairage":"x"}',
        'marie',
      ]) {
        expect(nomDepuisLienContact(texte), isNull, reason: texte);
      }
    });
  });
}
