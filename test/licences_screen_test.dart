import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/presentation/screens/legal/licences_screen.dart';

/// L'écran des licences n'est pas décoratif : il porte l'offre de code source
/// qu'exige l'AGPL. S'il plante à l'ouverture, l'offre n'existe plus.
///
/// Non couvert, faute de pouvoir l'être : le montage sous Cupertino, où rien
/// ne fournit de `Material` et où un `InkWell` nu échoue avec « No Material
/// widget found ». `AdaptiveScaffold` choisit sa branche sur `Platform.isIOS`,
/// c'est-à-dire sur la machine qui exécute, jamais sur un réglage que le test
/// pourrait feindre. D'où le `Material` transparent dans l'écran, posé par
/// précaution et non par mesure.
void main() {
  testWidgets("s'ouvre sous Material", (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LicencesScreen()));
    expect(find.text('Voir le code source'), findsOneWidget);
    expect(find.text('Licences des composants'), findsOneWidget);
  });
}
