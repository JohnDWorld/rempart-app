import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/plateforme.dart';
import 'cache_medias.dart';

/// Où en est la transcription d'un vocal : [texte] et [echec] nuls tant
/// qu'elle tourne.
typedef EtatTranscription = ({String? texte, String? echec});

/// Transcrit un vocal en texte, sur l'appareil seulement.
///
/// À la demande (« Transcrire » sous le vocal), jamais d'office : la
/// reconnaissance occupe le téléphone plusieurs secondes. Le résultat est
/// gardé le temps de la session, en mémoire seulement : écrit quelque part,
/// il serait une copie en clair d'un message chiffré.
class TranscriptionVocale extends ChangeNotifier {
  TranscriptionVocale._();

  static final instance = TranscriptionVocale._();

  static const _canal = MethodChannel('rempart/transcription');

  final _etats = <String, EtatTranscription>{};
  Future<bool>? _disponible;

  /// L'appareil sait-il transcrire sans rien envoyer ? Android 13 et plus,
  /// avec un reconnaisseur « sur l'appareil ».
  Future<bool> disponible() => _disponible ??= () async {
        if (!estAndroid) return false;
        try {
          return await _canal.invokeMethod<bool>('disponible') ?? false;
        } catch (_) {
          return false;
        }
      }();

  EtatTranscription? etat(Event event) => _etats[cleMedia(event)];

  Future<void> transcrire(Event event) async {
    final cle = cleMedia(event);
    final actuel = _etats[cle];
    // En cours, ou déjà transcrit. Un échec ou « aucune parole » se retente.
    if (actuel != null && actuel.echec == null && actuel.texte != '') {
      return;
    }
    _poser(cle, (texte: null, echec: null));
    File? fichier;
    try {
      final octets = (await event.downloadAndDecryptAttachment()).bytes;
      // Pas le dossier de cache : le système le vide quand la place manque,
      // fichier en cours de lecture compris (voir « Lecture des vidéos »).
      final dossier = Directory(
        '${(await getApplicationSupportDirectory()).path}/transcription',
      );
      await dossier.create(recursive: true);
      fichier = File('${dossier.path}/${cle.hashCode}.m4a');
      await fichier.writeAsBytes(octets, flush: true);
      final texte = await _canal.invokeMethod<String>(
        'transcrire',
        {'chemin': fichier.path, 'langue': 'fr-FR'},
      );
      _poser(cle, (texte: texte ?? '', echec: null));
    } on PlatformException catch (e) {
      debugPrint('TranscriptionVocale : ${e.code} (${e.message})');
      _poser(cle, (texte: null, echec: messageDEchec(e.code)));
    } catch (e) {
      debugPrint('TranscriptionVocale : $e');
      _poser(cle, (texte: null, echec: messageDEchec(null)));
    } finally {
      // Le vocal déchiffré ne reste pas sur le disque.
      if (fichier != null && fichier.existsSync()) fichier.deleteSync();
    }
  }

  void _poser(String cle, EtatTranscription etat) {
    _etats[cle] = etat;
    notifyListeners();
  }
}

/// Ce que l'écran dit quand la transcription échoue.
String messageDEchec(String? code) => switch (code) {
      'indisponible' => 'Transcription indisponible sur cet appareil',
      'langue' =>
        'Le français se télécharge sur le téléphone, réessayez dans un moment',
      _ => 'Transcription impossible',
    };
