import 'dart:io';

import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/plateforme.dart';
import '../../core/utils/dimensions_image.dart';

/// Ce qu'on sait d'une vidéo avant de l'envoyer.
class AnalyseVideo {
  const AnalyseVideo({this.vignette, this.largeur, this.hauteur, this.dureeMs});

  /// Une image de la vidéo (JPEG, 800 px au plus) : sans elle, le
  /// destinataire ne voit qu'un fond sombre à la place de la vidéo.
  final Uint8List? vignette;
  final int? largeur;
  final int? hauteur;
  final int? dureeMs;
}

/// Vignette, format et durée d'une vidéo, par les outils natifs de
/// l'appareil (Android et iOS ; null ailleurs, la vidéo part sans).
///
/// Passe par un fichier : les deux outils ne lisent que ça. Il est effacé
/// dans tous les cas.
Future<AnalyseVideo?> analyserVideo(Uint8List octets) async {
  if (!estAndroid && !estIOS) return null;
  // Même raison que pour la lecture : le dossier de cache d'Android peut être
  // vidé en cours de route quand la place manque.
  final base = estAndroid
      ? await getApplicationSupportDirectory()
      : await getTemporaryDirectory();
  final dossier = Directory('${base.path}/envoi');
  await dossier.create(recursive: true);
  final fichier =
      File('${dossier.path}/video-${DateTime.now().microsecondsSinceEpoch}');
  await fichier.writeAsBytes(octets, flush: true);
  try {
    Uint8List? vignette;
    try {
      vignette = await FcNativeVideoThumbnail().saveThumbnailToBytes(
        srcFile: fichier.path,
        width: 800,
        height: 800,
        format: 'jpeg',
        quality: 80,
      );
    } catch (e) {
      debugPrint('AnalyseVideo : pas de vignette ($e)');
    }

    int? largeur;
    int? hauteur;
    int? dureeMs;
    final lecteur = VideoPlayerController.file(fichier);
    try {
      await lecteur.initialize();
      final taille = lecteur.value.size;
      if (taille.width > 0 && taille.height > 0) {
        largeur = taille.width.round();
        hauteur = taille.height.round();
      }
      dureeMs = lecteur.value.duration.inMilliseconds;
    } catch (e) {
      debugPrint('AnalyseVideo : durée illisible ($e)');
    } finally {
      await lecteur.dispose();
    }

    final dimensionsVignette =
        vignette == null ? null : await dimensionsImage(vignette);
    final (l, h) = orienter(
      video: largeur == null ? null : (largeur, hauteur!),
      vignette: dimensionsVignette,
    );
    return AnalyseVideo(
      vignette: vignette,
      largeur: l,
      hauteur: h,
      dureeMs: dureeMs == 0 ? null : dureeMs,
    );
  } finally {
    if (await fichier.exists()) await fichier.delete();
  }
}

/// Largeur et hauteur de la vidéo telle qu'on la regarde.
///
/// Le lecteur d'Android rend les dimensions AVANT rotation : une vidéo filmée
/// en portrait sort souvent « paysage ». La vignette, elle, sort à l'endroit :
/// c'est elle qui dit l'orientation, la vidéo donnant les vraies dimensions.
/// Sans la vidéo, les proportions de la vignette suffisent.
(int?, int?) orienter({(int, int)? video, (int, int)? vignette}) {
  if (video == null) return vignette ?? (null, null);
  final (l, h) = video;
  if (vignette == null) return (l, h);
  final portrait = vignette.$2 > vignette.$1;
  return portrait == (h > l) ? (l, h) : (h, l);
}
