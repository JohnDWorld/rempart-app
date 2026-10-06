import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Fait télécharger des octets par le navigateur, sous le nom donné.
///
/// Le navigateur n'a ni galerie ni dossier temporaire : enregistrer une photo
/// passait par `getTemporaryDirectory`, qui n'existe pas ici, et échouait sur
/// une `MissingPluginException` (relevé le 2026-10-06). Un lien `download`
/// vers un Blob en mémoire est le geste ordinaire d'un site web.
Future<void> telechargerDansLeNavigateur(
  Uint8List octets, {
  required String nom,
  required String mime,
}) async {
  final blob = web.Blob([octets.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final lien = web.HTMLAnchorElement()
    ..href = url
    ..download = nom;
  web.document.body?.append(lien);
  lien
    ..click()
    ..remove();
  // Le navigateur lit le Blob après le clic : le rendre aussitôt couperait le
  // téléchargement.
  await Future<void>.delayed(const Duration(seconds: 2));
  web.URL.revokeObjectURL(url);
}
