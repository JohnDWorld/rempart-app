import 'dart:typed_data';
import 'dart:ui' as ui;

/// Largeur et hauteur d'une image encodée (JPEG, PNG, WebP...), sans la
/// décoder : seul l'en-tête est lu, par le décodeur natif du moteur.
///
/// Null si le format n'est pas reconnu.
Future<(int, int)?> dimensionsImage(Uint8List octets) async {
  ui.ImmutableBuffer? tampon;
  ui.ImageDescriptor? descripteur;
  try {
    tampon = await ui.ImmutableBuffer.fromUint8List(octets);
    descripteur = await ui.ImageDescriptor.encoded(tampon);
    if (descripteur.width <= 0 || descripteur.height <= 0) return null;
    return (descripteur.width, descripteur.height);
  } catch (_) {
    return null;
  } finally {
    descripteur?.dispose();
    tampon?.dispose();
  }
}
