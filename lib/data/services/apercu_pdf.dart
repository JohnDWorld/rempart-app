import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/plateforme.dart';

/// Les pages d'un PDF, rendues par le moteur PDF d'Android (`ApercuPdf.kt`,
/// canal `rempart/pdf`) : aucune bibliothèque de plus, et le fichier
/// déchiffré ne quitte pas Rempart.
///
/// Android seulement. Sur iPhone il faudrait PDFKit (donc le Mac), et le
/// navigateur sait afficher un PDF tout seul.
class ApercuPdf {
  const ApercuPdf();

  static const _canal = MethodChannel('rempart/pdf');

  bool get disponible => estAndroid;

  /// Écrit le PDF là où le moteur d'Android peut le lire, et rend son chemin.
  ///
  /// Le dossier est vidé à chaque ouverture : un aperçu interrompu par
  /// l'arrêt de l'application ne laisse rien en clair. Pas le dossier de
  /// cache, que le système vide quand la place manque, fichier ouvert compris
  /// (même piège que pour les vidéos).
  Future<String> deposer(Uint8List octets) async {
    final racine = await getApplicationSupportDirectory();
    final dossier = Directory('${racine.path}/apercu');
    if (dossier.existsSync()) await dossier.delete(recursive: true);
    await dossier.create(recursive: true);
    final fichier = File('${dossier.path}/document.pdf');
    await fichier.writeAsBytes(octets, flush: true);
    return fichier.path;
  }

  Future<void> effacer(String chemin) async {
    try {
      await File(chemin).delete();
    } on FileSystemException {
      // Déjà parti : l'ouverture suivante vide le dossier de toute façon.
    }
  }

  /// Lève si le PDF est protégé par un mot de passe ou abîmé.
  Future<int> nombreDePages(String chemin) async =>
      (await _canal.invokeMethod<int>('pages', {'chemin': chemin}))!;

  /// La page [index] (à partir de 0), large de [largeur] pixels, en PNG.
  Future<Uint8List> page(String chemin, int index, int largeur) async =>
      (await _canal.invokeMethod<Uint8List>(
        'page',
        {'chemin': chemin, 'index': index, 'largeur': largeur},
      ))!;
}
