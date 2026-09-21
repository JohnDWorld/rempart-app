import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/app/app.dart';

/// Les libellés que Flutter fournit lui-même doivent être en français.
///
/// Ils ne viennent d'aucun de nos fichiers : « Coller », « Tout
/// sélectionner », les mois d'un sélecteur de date sortent des délégués de
/// localisation. Avec les délégués `Default*`, ils restent anglais quoi qu'on
/// demande, et le menu d'un appui long proposait « Paste » au milieu d'une
/// application entièrement française.
void main() {
  testWidgets('les libellés de Flutter sont en français', (tester) async {
    late MaterialLocalizations material;
    late CupertinoLocalizations cupertino;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr', 'FR'),
        supportedLocales: languesPrisesEnCharge,
        localizationsDelegates: delegationsLocalisation,
        home: Builder(
          builder: (context) {
            material = MaterialLocalizations.of(context);
            cupertino = CupertinoLocalizations.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(material.pasteButtonLabel, 'Coller');
    expect(material.selectAllButtonLabel, 'Tout sélectionner');
    // Les deux mondes, parce que l'application monte l'un ou l'autre selon le
    // système, et que l'oubli d'un seul ne se verrait que sur un iPhone.
    expect(cupertino.pasteButtonLabel, 'Coller');
  });
}
