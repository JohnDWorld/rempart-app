import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/presentation/screens/auth/mot_de_passe_oublie_screen.dart';

/// Un lien de réinitialisation refusé (périmé, ou déjà servi) ramène à la
/// demande d'un nouveau lien. Sans l'encart, la personne retombait devant le
/// formulaire qu'elle venait de remplir, sans rien comprendre à ce qui s'était
/// passé.
void main() {
  Future<void> ouvrir(WidgetTester tester, {required bool lienPerime}) =>
      tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: MotDePasseOublieScreen(lienPerime: lienPerime),
          ),
        ),
      );

  testWidgets('dit pourquoi le lien a été refusé', (tester) async {
    await ouvrir(tester, lienPerime: true);
    expect(find.textContaining("n'est plus valable"), findsOneWidget);
  });

  testWidgets('offre un retour quand rien ne le précède', (tester) async {
    // Seul dans la pile, comme quand on arrive par le lien du courriel.
    await ouvrir(tester, lienPerime: true);
    expect(find.text('Revenir à la connexion'), findsOneWidget);
  });

  testWidgets("se tait quand on vient d'ailleurs", (tester) async {
    await ouvrir(tester, lienPerime: false);
    expect(find.textContaining("n'est plus valable"), findsNothing);
  });
}
