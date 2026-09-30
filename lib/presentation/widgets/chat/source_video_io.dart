import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../../core/plateforme.dart';

/// Lecteur d'une vidéo déchiffrée, et de quoi effacer sa copie en clair.
///
/// Le lecteur natif ne lit qu'un fichier ou une adresse : la vidéo passe par
/// un fichier, que [liberer] efface à la fermeture. Rien ne reste en clair
/// sur l'appareil une fois la vidéo regardée.
///
/// Sur Android, surtout pas le dossier de cache : quand la place manque, le
/// système le vide, fichier ouvert compris, et la vidéo tombait en erreur au
/// premier retour en arrière (`installd: Purging …/cache/video-…`, vu le
/// 2026-09-30). Le dossier des fichiers de l'application n'est jamais vidé
/// d'office, et nos règles l'excluent déjà des sauvegardes. Sur iOS, le
/// dossier temporaire, ni sauvegardé ni purgé pendant que l'application
/// tourne.
Future<(VideoPlayerController, Future<void> Function())> ouvrirVideo(
  Uint8List octets, {
  required String nom,
  required String mime,
}) async {
  final base = estAndroid
      ? await getApplicationSupportDirectory()
      : await getTemporaryDirectory();
  final dossier = Directory('${base.path}/lecture');
  // Une seule vidéo se lit à la fois : ce qui traîne ici vient d'une lecture
  // interrompue (application tuée), et n'a plus à rester en clair.
  if (await dossier.exists()) await dossier.delete(recursive: true);
  await dossier.create(recursive: true);

  final fichier = File('${dossier.path}/video-$nom');
  await fichier.writeAsBytes(octets, flush: true);
  Future<void> liberer() async {
    if (await fichier.exists()) await fichier.delete();
  }

  return (VideoPlayerController.file(fichier), liberer);
}
