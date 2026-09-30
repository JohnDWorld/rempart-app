import 'dart:js_interop';
import 'dart:typed_data';

import 'package:video_player/video_player.dart';
import 'package:web/web.dart' as web;

/// Lecteur d'une vidéo déchiffrée, dans le navigateur.
///
/// Pas de fichier ici : la vidéo devient un lien en mémoire (Blob), que
/// [liberer] rend au navigateur à la fermeture du lecteur.
Future<(VideoPlayerController, Future<void> Function())> ouvrirVideo(
  Uint8List octets, {
  required String nom,
  required String mime,
}) async {
  final blob = web.Blob(
    [octets.toJS].toJS,
    web.BlobPropertyBag(type: mime),
  );
  final url = web.URL.createObjectURL(blob);
  Future<void> liberer() async => web.URL.revokeObjectURL(url);
  return (VideoPlayerController.networkUrl(Uri.parse(url)), liberer);
}
