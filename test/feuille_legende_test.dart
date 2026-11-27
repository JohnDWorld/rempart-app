import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:rempart_app/app/theme.dart';
import 'package:rempart_app/presentation/widgets/adaptive/adaptive.dart';
import 'package:rempart_app/presentation/widgets/chat/feuille_legende.dart';

/// Le clavier des emojis de Gboard, plus haut que celui des lettres,
/// recouvrait la légende et « Envoyer » (relevé le 2026-11-27) : la feuille
/// était une colonne de hauteur fixe, dont le bas était coupé.
void main() {
  const ecran = Size(393, 851);

  /// Une photo en hauteur, au-delà de 300 Ko pour que l'interrupteur HD
  /// s'affiche. Le PNG d'un aplat est minuscule : les octets ajoutés après
  /// sa fin ne sont pas lus.
  Future<MatrixImageFile> photoDebout(WidgetTester t) async {
    final png = await t.runAsync(() async {
      final enregistreur = ui.PictureRecorder();
      Canvas(enregistreur).drawRect(
        const Rect.fromLTWH(0, 0, 600, 1000),
        Paint()..color = Colors.teal,
      );
      final image = await enregistreur.endRecording().toImage(600, 1000);
      final octets = await image.toByteData(format: ui.ImageByteFormat.png);
      return octets!.buffer.asUint8List();
    });
    return MatrixImageFile(
      bytes: Uint8List.fromList([...png!, ...List.filled(400 * 1024, 0)]),
      name: 'photo.png',
      mimeType: 'image/png',
    );
  }

  Future<void> ouvrir(WidgetTester t, {required double clavier}) async {
    t.view.devicePixelRatio = 3;
    t.view.physicalSize = ecran * 3;
    t.view.viewInsets = FakeViewPadding(bottom: clavier * 3);
    addTearDown(t.view.reset);
    final photo = await photoDebout(t);
    await t.pumpWidget(
      MaterialApp(
        theme: RempartTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => feuilleAdaptative<ChoixEnvoi>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => FeuilleLegende(fichiers: [photo]),
                ),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('ouvrir'));
    await t.pumpAndSettle();
    // Décoder l'aperçu, sans quoi l'image ne prend aucune hauteur.
    await t.runAsync(() async {
      for (final element in find.byType(Image).evaluate()) {
        await precacheImage((element.widget as Image).image, element);
      }
    });
    await t.pumpAndSettle();
  }

  testWidgets('la légende et « Envoyer » restent au-dessus du clavier',
      (t) async {
    const clavier = 400.0;
    await ouvrir(t, clavier: clavier);
    const hautDuClavier = 851 - clavier;

    expect(t.getRect(find.byType(TextField)).bottom,
        lessThanOrEqualTo(hautDuClavier));
    expect(t.getRect(find.text('Envoyer')).bottom,
        lessThanOrEqualTo(hautDuClavier));
    // L'aperçu se réduit pour leur faire place, sans disparaître.
    expect(t.getSize(find.byType(Image)).height, greaterThan(80));

    // La qualité reste à portée.
    final hd = find.byType(Switch);
    await t.ensureVisible(hd);
    await t.pumpAndSettle();
    expect(t.getRect(hd).bottom, lessThanOrEqualTo(hautDuClavier));
    await t.tap(hd);
    await t.pumpAndSettle();
    expect(find.textContaining('telles quelles'), findsOneWidget);
  });

  testWidgets("clavier fermé, l'aperçu garde sa pleine taille", (t) async {
    await ouvrir(t, clavier: 0);
    expect(t.getSize(find.byType(Image)).height, 260);
  });
}
