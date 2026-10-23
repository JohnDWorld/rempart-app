import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/plateforme.dart';

/// Le petit côté d'une vidéo allégée : 720p, quelle que soit l'orientation.
const coteCourtVise = 720;

/// Débit de l'image d'une vidéo allégée : environ 16 Mo par minute avec le
/// son, nette sur un téléphone, correcte sur un ordinateur.
const debitVise = 2000000;

/// En dessous, l'image se dégrade trop : mieux vaut dire que la vidéo est
/// trop longue qu'envoyer de la bouillie.
const debitMinimum = 400000;

/// Ce que le son coûte en plus (AAC).
const debitSon = 128000;

/// Ce qu'on fait d'une vidéo avant l'envoi.
sealed class PlanVideo {
  const PlanVideo();
}

/// Elle part telle quelle : déjà légère, ou rien à y gagner.
class GarderVideo extends PlanVideo {
  const GarderVideo();
}

class ReencoderVideo extends PlanVideo {
  const ReencoderVideo({required this.debit, required this.coteCourt});

  /// Débit de l'image, en bits par seconde.
  final int debit;

  /// Petit côté visé en pixels, ou 0 pour garder la taille d'origine.
  final int coteCourt;
}

/// La vidéo ne tient pas sous la limite du serveur, même allégée.
class VideoTropLongue implements Exception {
  const VideoTropLongue(this.dureeMs);

  final int dureeMs;

  @override
  String toString() => 'vidéo trop longue pour le serveur, même allégée '
      '(${(dureeMs / 60000).round()} min) : envoyez-en un extrait';
}

/// Ce qu'il faut faire d'une vidéo de [taille] octets, longue de [dureeMs],
/// pour qu'elle parte sous [limite] (la limite d'envoi du serveur, si elle
/// est connue).
///
/// Lève [VideoTropLongue] si même le débit minimum ne la ferait pas tenir,
/// et qu'elle ne tient pas déjà telle quelle.
PlanVideo planCompression({
  required int taille,
  required int dureeMs,
  required int largeur,
  required int hauteur,
  int? limite,
}) {
  var debit = debitVise;
  if (limite != null && dureeMs > 0) {
    // 10 % de marge : l'en-tête du fichier et les écarts de l'encodeur.
    final possible = (limite * 0.9 * 8 * 1000 / dureeMs).floor() - debitSon;
    if (possible < debitMinimum) {
      if (taille <= limite) return const GarderVideo();
      throw VideoTropLongue(dureeMs);
    }
    debit = math.min(debit, possible);
  }
  final coteCourt = math.min(largeur, hauteur);
  final debitActuel = dureeMs > 0 ? taille * 8 * 1000 ~/ dureeMs : null;
  // Déjà en 720p ou moins, à un débit proche : réencoder ne ferait que
  // perdre un peu de qualité.
  if (coteCourt > 0 &&
      coteCourt <= coteCourtVise &&
      debitActuel != null &&
      debitActuel <= debit * 1.25 &&
      (limite == null || taille <= limite)) {
    return const GarderVideo();
  }
  return ReencoderVideo(
    debit: debit,
    coteCourt: coteCourt > coteCourtVise ? coteCourtVise : 0,
  );
}

/// Allège une vidéo avant l'envoi, comme WhatsApp : 720p, H.264, par
/// l'encodeur matériel du téléphone (`CompressionVideo.kt`, Media3
/// Transformer). Une vidéo de 100 Mo, refusée par le serveur (50 Mo),
/// partait sur WhatsApp en une douzaine (relevé le 2026-10-23).
///
/// Android seulement : sur iPhone il faudra AVAssetExportSession (donc le
/// Mac), et le navigateur n'a pas d'encodeur à portée ; la vidéo y part
/// telle quelle.
class CompressionVideo {
  const CompressionVideo._();

  static const _canal = MethodChannel('rempart/video');

  static bool get disponible => estAndroid;

  /// La vidéo allégée, ou null si elle doit partir telle quelle (rien à y
  /// gagner, ou compression impossible : mieux vaut une vidéo lourde qu'une
  /// vidéo perdue). Lève [VideoTropLongue].
  ///
  /// [progression] reçoit l'avancement, de 0 à 100.
  static Future<Uint8List?> alleger(
    Uint8List octets, {
    int? limite,
    ValueChanged<int>? progression,
  }) async {
    if (!disponible) return null;
    // Le moteur ne lit et n'écrit que des fichiers. Le dossier est vidé avant
    // et après : rien ne reste en clair. Pas le dossier de cache, que le
    // système vide quand la place manque, fichier ouvert compris.
    final racine = await getApplicationSupportDirectory();
    final dossier = Directory('${racine.path}/compression');
    if (dossier.existsSync()) await dossier.delete(recursive: true);
    await dossier.create(recursive: true);
    final entree = File('${dossier.path}/entree');
    final sortie = File('${dossier.path}/sortie.mp4');
    try {
      await entree.writeAsBytes(octets, flush: true);
      final mesure = Map<String, dynamic>.from(
        (await _canal.invokeMethod<Map<Object?, Object?>>(
          'mesurer',
          {'entree': entree.path},
        ))!,
      );
      final plan = planCompression(
        taille: octets.length,
        dureeMs: (mesure['dureeMs'] as num).toInt(),
        largeur: (mesure['largeur'] as num).toInt(),
        hauteur: (mesure['hauteur'] as num).toInt(),
        limite: limite,
      );
      if (plan is! ReencoderVideo) return null;

      _canal.setMethodCallHandler((appel) async {
        if (appel.method == 'progression') {
          progression?.call(appel.arguments as int);
        }
      });
      await _canal.invokeMethod<void>('compresser', {
        'entree': entree.path,
        'sortie': sortie.path,
        'debit': plan.debit,
        'coteCourt': plan.coteCourt,
      });
      final reduite = await sortie.readAsBytes();
      return reduite.length < octets.length ? reduite : null;
    } on PlatformException catch (e) {
      debugPrint('Compression vidéo : impossible, original envoyé ($e)');
      return null;
    } finally {
      _canal.setMethodCallHandler(null);
      if (dossier.existsSync()) await dossier.delete(recursive: true);
    }
  }
}
