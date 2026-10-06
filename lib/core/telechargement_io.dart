import 'dart:typed_data';

/// Hors navigateur, une pièce jointe va dans la galerie ou passe par la
/// feuille de partage : rien ne doit appeler ceci.
Future<void> telechargerDansLeNavigateur(
  Uint8List octets, {
  required String nom,
  required String mime,
}) async =>
    throw UnsupportedError('téléchargement réservé au navigateur');
