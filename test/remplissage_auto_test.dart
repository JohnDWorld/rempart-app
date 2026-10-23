import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/presentation/screens/auth/login_screen.dart';

/// Les champs de connexion se présentent aux gestionnaires de mots de passe.
///
/// Sans indication, la version web marque chaque champ
/// `autocomplete="off"` : Proton Pass voyait l'identifiant enregistré pour le
/// site, mais ne le proposait pas dans le champ (relevé le 2026-10-23).
void main() {
  // L'écran lit la configuration au démarrage (adresse proposée d'office).
  setUpAll(() => dotenv.loadFromString(envString: 'IS_LOCAL=false'));

  testWidgets('identifiant et mot de passe, dans un même groupe',
      (tester) async {
    // La police des tests est plus large que la vraie : dans les 420 points
    // du formulaire, la ligne « Pas encore de compte ? » y déborderait.
    tester.platformDispatcher.textScaleFactorTestValue = 0.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginScreen())),
    );

    final champs = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((c) => c.autofillHints?.toList())
        .toList();
    expect(champs, [
      [AutofillHints.username, AutofillHints.email],
      [AutofillHints.password],
    ]);
    expect(
      find.ancestor(
        of: find.byType(TextField).first,
        matching: find.byType(AutofillGroup),
      ),
      findsOneWidget,
    );
  });
}
