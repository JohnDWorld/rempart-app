import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/core/utils/verification_nom_utilisateur.dart';

/// La vérification du nom d'utilisateur pendant la frappe : règles d'abord,
/// puis la base, une fois la saisie arrêtée.
void main() {
  const delai = Duration(milliseconds: 500);

  testWidgets('un nom libre est annoncé disponible, après la pause',
      (tester) async {
    final demandes = <String>[];
    final v = VerificationNomUtilisateur((nom) async {
      demandes.add(nom);
      return null;
    });
    addTearDown(v.dispose);

    v.saisie('@Marie.D ');
    await tester.pump(delai ~/ 2);
    expect(demandes, isEmpty, reason: 'pas de requête à chaque frappe');
    await tester.pump(delai);
    expect(demandes, ['marie.d']);
    expect(v.etat, EtatNomUtilisateur.disponible);
    expect(v.annonce, '@marie.d est disponible');
    expect(v.erreur, isNull);
  });

  testWidgets('un nom pris est refusé, avec la raison', (tester) async {
    final v = VerificationNomUtilisateur((_) async => 'pris');
    addTearDown(v.dispose);
    v.saisie('thomas');
    await tester.pump(delai);
    expect(v.etat, EtatNomUtilisateur.refuse);
    expect(v.erreur, 'Ce nom est déjà pris');
  });

  testWidgets('une règle enfreinte se dit sans interroger la base',
      (tester) async {
    var demandes = 0;
    final v = VerificationNomUtilisateur((_) async {
      demandes++;
      return null;
    });
    addTearDown(v.dispose);
    v.saisie('ma');
    await tester.pump(delai);
    expect(v.etat, EtatNomUtilisateur.refuse);
    expect(v.erreur, 'Entre 3 et 30 caractères');
    expect(demandes, 0);
  });

  testWidgets('une réponse arrivée après une nouvelle frappe est ignorée',
      (tester) async {
    final reponses = <String, Completer<String?>>{};
    final v = VerificationNomUtilisateur(
      (nom) => (reponses[nom] = Completer<String?>()).future,
    );
    addTearDown(v.dispose);

    v.saisie('marie');
    await tester.pump(delai);
    expect(v.etat, EtatNomUtilisateur.verification);
    v.saisie('marie.d');
    reponses['marie']!.complete('pris');
    await tester.pump();
    expect(v.erreur, isNull, reason: '« marie » pris ne dit rien de marie.d');

    await tester.pump(delai);
    reponses['marie.d']!.complete(null);
    await tester.pump();
    expect(v.etat, EtatNomUtilisateur.disponible);
  });

  testWidgets('son propre nom ne se vérifie pas', (tester) async {
    var demandes = 0;
    final v = VerificationNomUtilisateur((_) async {
      demandes++;
      return 'pris';
    });
    addTearDown(v.dispose);
    v.saisie('thomas', actuel: 'thomas');
    await tester.pump(delai);
    expect(demandes, 0);
    expect(v.etat, EtatNomUtilisateur.inconnu);
  });

  testWidgets("sans réseau, rien n'est affirmé", (tester) async {
    final v =
        VerificationNomUtilisateur((_) async => throw Exception('hors ligne'));
    addTearDown(v.dispose);
    v.saisie('marie.d');
    await tester.pump(delai);
    expect(v.etat, EtatNomUtilisateur.inconnu);
    expect(v.erreur, isNull);
  });
}
