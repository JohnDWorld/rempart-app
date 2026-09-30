import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../../core/plateforme.dart';

/// Un fichier reçu d'une autre application, copié dans le cache par Android.
class FichierPartage {
  const FichierPartage({required this.chemin, required this.nom, this.type});

  final String chemin;
  final String nom;
  final String? type;
}

/// Ce qu'une autre application a confié à Rempart par « Partager ».
class Partage {
  const Partage({required this.fichiers, this.texte});

  final List<FichierPartage> fichiers;

  /// Texte accompagnant le partage : un lien le plus souvent, ou la légende
  /// qu'une application joint à ses photos.
  final String? texte;

  /// Les fichiers, prêts à passer par le chemin d'envoi habituel.
  Future<List<matrix.MatrixFile>> versMatrixFiles() async => [
        for (final fichier in fichiers)
          matrix.MatrixFile.fromMimeType(
            bytes: await File(fichier.chemin).readAsBytes(),
            name: fichier.nom,
            mimeType: fichier.type,
          ),
      ];
}

/// Réception des partages venus d'autres applications (Android seulement).
///
/// La moitié native est `Partage.kt`. Un partage attend dans [enAttente]
/// jusqu'à ce que l'accueil l'ouvre : l'application peut avoir été lancée par
/// le partage lui-même, et il faut alors attendre la connexion.
class PartageEntrant {
  PartageEntrant._();

  static final instance = PartageEntrant._();

  static const _canal = MethodChannel('rempart/partage');

  final enAttente = ValueNotifier<Partage?>(null);

  void init() {
    if (!estAndroid) return;
    _canal.setMethodCallHandler((appel) async {
      if (appel.method == 'nouveau') await _relever();
    });
    unawaited(_relever());
  }

  Future<void> _relever() async {
    try {
      final brut = await _canal.invokeMapMethod<String, Object?>('prendre');
      if (brut == null) return;
      enAttente.value = Partage(
        fichiers: [
          for (final f in (brut['fichiers'] as List? ?? const [])
              .cast<Map<Object?, Object?>>())
            FichierPartage(
              chemin: f['chemin']! as String,
              nom: f['nom']! as String,
              type: f['type'] as String?,
            ),
        ],
        texte: brut['texte'] as String?,
      );
    } catch (e) {
      debugPrint('Partage : lecture impossible ($e)');
    }
  }

  /// Retire le partage en attente et le rend.
  Partage? prendre() {
    final partage = enAttente.value;
    enAttente.value = null;
    return partage;
  }
}

/// Ce que contient un partage, en quelques mots : « 3 photos », « 1 fichier ».
///
/// [types] sont les types MIME des fichiers (null si inconnu). Sans fichier,
/// le texte lui-même tient lieu de résumé.
String resumePartage(List<String?> types, String? texte) {
  final n = types.length;
  if (n == 0) return texte?.trim() ?? '';
  bool tous(String prefixe) =>
      types.every((t) => t != null && t.startsWith(prefixe));
  if (tous('image/')) return n == 1 ? '1 photo' : '$n photos';
  if (tous('video/')) return n == 1 ? '1 vidéo' : '$n vidéos';
  if (types.every(
      (t) => t != null && (t.startsWith('image/') || t.startsWith('video/')))) {
    return '$n photos et vidéos';
  }
  return n == 1 ? '1 fichier' : '$n fichiers';
}
