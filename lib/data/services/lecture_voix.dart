import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../core/utils/texte_a_lire.dart';

/// Lit un message à voix haute, avec la voix du système.
///
/// Rien ne quitte l'appareil : la synthèse est celle d'Android, d'iOS ou du
/// navigateur. Une seule lecture à la fois : en lancer une autre arrête la
/// précédente, et quitter la conversation l'arrête aussi (`ChatScreen`).
class LectureVoix {
  LectureVoix._();

  static final instance = LectureVoix._();

  final _tts = FlutterTts();
  Future<void>? _pret;

  /// L'identifiant du message en cours de lecture, ou `null`.
  final enCours = ValueNotifier<String?>(null);

  Future<void> lire(String id, String texte) async {
    await arreter();
    _pret ??= () async {
      // Chaque morceau attend la fin du précédent : sans cela, Android les
      // jouerait par-dessus l'un l'autre.
      await _tts.awaitSpeakCompletion(true);
      await _tts.setLanguage('fr-FR');
    }();
    await _pret;
    enCours.value = id;
    try {
      for (final morceau in morceauxALire(texte)) {
        // Arrêtée, ou remplacée par une autre lecture, entre deux morceaux.
        if (enCours.value != id) return;
        await _tts.speak(morceau);
      }
    } catch (e) {
      debugPrint('LectureVoix : lecture impossible ($e)');
    } finally {
      if (enCours.value == id) enCours.value = null;
    }
  }

  Future<void> arreter() async {
    if (enCours.value == null) return;
    enCours.value = null;
    await _tts.stop();
  }
}
