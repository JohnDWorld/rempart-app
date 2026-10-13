import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import '../../core/plateforme.dart';
import 'cache_medias.dart';

/// Ce qu'on dit quand le vocal est bien arrivé mais ne se lit pas.
///
/// Sur le web, la cause est presque toujours la même et elle ne vient pas de
/// Rempart : le vocal est de l'AAC dans un M4A, format qu'un navigateur sans
/// codec propriétaire refuse de décoder. Mesuré : Opera sous Linux rend une
/// chaîne vide à `canPlayType('audio/mp4; codecs="mp4a.40.2"')` là où Chrome
/// rend « probably ». Dire « vocal illisible » ferait accuser le message, qui
/// est intact et s'écoute ailleurs.
final echecDeLecture =
    estWeb ? 'Ce navigateur ne lit pas ce format' : 'Vocal illisible';

/// Le lecteur des vocaux, un seul pour toutes les bulles.
///
/// Il vivait dans chaque bulle, et c'est ce qui trompait : la liste du fil
/// réutilise ses éléments par position (elle ne sait pas suivre une clé), et
/// quand un message arrivait pendant une écoute, l'état de la bulle qui jouait
/// passait à sa voisine. On voyait avancer le deuxième vocal, on entendait le
/// premier (relevé le 2026-10-13). Le lecteur suit désormais son vocal par sa
/// clé (`cleMedia`), et une bulle n'est plus qu'une vue, qui demande où en est
/// SON vocal. L'écoute survit donc aux messages qui arrivent, et un seul vocal
/// joue à la fois.
class LecteurVocal extends ChangeNotifier {
  LecteurVocal._();

  static final instance = LecteurVocal._();

  /// Créé au premier vocal écouté, pas au démarrage : beaucoup de sessions
  /// n'en écoutent aucun.
  AudioPlayer? _lecteur;

  /// Le vocal armé dans le lecteur.
  String? _cle;
  bool _joue = false;
  Duration _position = Duration.zero;
  String? _enChargement;
  final _echecs = <String, String>{};

  /// Les derniers vocaux déchiffrés, pour réécouter sans retélécharger.
  final _octets = <String, Uint8List>{};
  static const _octetsGardes = 5;

  bool joue(String cle) => _cle == cle && _joue;
  Duration position(String cle) => _cle == cle ? _position : Duration.zero;
  bool enChargement(String cle) => _enChargement == cle;
  String? echec(String cle) => _echecs[cle];

  AudioPlayer get _lecteurPret => _lecteur ??= _creer();

  AudioPlayer _creer() {
    final lecteur = AudioPlayer();
    // `release` (le défaut sur Android) libère la source à la fin du vocal :
    // il faudrait la reposer pour réécouter, et toute position choisie serait
    // perdue. `stop` garde le lecteur chargé.
    unawaited(lecteur.setReleaseMode(ReleaseMode.stop));
    lecteur.onPlayerStateChanged.listen((etat) {
      _joue = etat == PlayerState.playing;
      notifyListeners();
    });
    lecteur.onPositionChanged.listen((p) {
      _position = p;
      notifyListeners();
    });
    // Les pannes de lecture n'arrivent pas en exception : le lecteur les pose
    // sur son flux d'événements, et sans cette écoute elles se perdaient dans
    // la zone asynchrone, le bouton restant muet.
    lecteur.eventStream.listen(
      (_) {},
      onError: (Object erreur) {
        debugPrint('LecteurVocal: lecture impossible ($erreur)');
        final cle = _cle;
        if (cle != null) _echecs[cle] = echecDeLecture;
        notifyListeners();
      },
    );
    lecteur.onPlayerComplete.listen((_) {
      // Revenir au début : sans cela, un second appui ne relance rien.
      unawaited(lecteur.seek(Duration.zero));
      _position = Duration.zero;
      notifyListeners();
    });
    return lecteur;
  }

  /// Arme le vocal de [event] s'il ne l'est pas déjà. Rend faux si rien n'est
  /// jouable, l'échec étant alors à lire par [echec].
  Future<bool> _armer(Event event) async {
    final cle = cleMedia(event);
    if (_cle == cle) return true;
    var octets = _octets[cle];
    if (octets == null) {
      _enChargement = cle;
      notifyListeners();
      try {
        octets = (await event.downloadAndDecryptAttachment()).bytes;
      } catch (e) {
        debugPrint('LecteurVocal: vocal non récupéré ($e)');
        _echecs[cle] = 'Vocal non récupéré';
        return false;
      } finally {
        if (_enChargement == cle) _enChargement = null;
        notifyListeners();
      }
      _octets[cle] = octets;
      if (_octets.length > _octetsGardes) _octets.remove(_octets.keys.first);
    }
    try {
      final lecteur = _lecteurPret;
      // Un seul vocal à la fois : celui qui jouait s'arrête.
      await lecteur.stop();
      _cle = cle;
      _position = Duration.zero;
      notifyListeners();
      // La taille part au journal : un vocal vide ou resté chiffré se
      // reconnaît là, et pas à l'écran, où les deux se ressemblent.
      debugPrint('LecteurVocal: vocal prêt, ${octets.length} octets');
      await lecteur.setSourceBytes(octets, mimeType: 'audio/mp4');
      return true;
    } catch (e) {
      debugPrint('LecteurVocal: lecture impossible ($e)');
      _echecs[cle] = echecDeLecture;
      _cle = null;
      notifyListeners();
      return false;
    }
  }

  /// Lance le vocal de [event], ou le met en pause s'il joue.
  Future<void> basculer(Event event, {required double vitesse}) async {
    if (joue(cleMedia(event))) {
      await _lecteurPret.pause();
      return;
    }
    if (!await _armer(event)) return;
    // La vitesse se repose à chaque lecture : selon les plateformes, le
    // lecteur la ramène à 1 en changeant de source.
    await _lecteurPret.setPlaybackRate(vitesse);
    await _lecteurPret.resume();
  }

  /// Se place dans le vocal de [event], sans lancer la lecture : on peut
  /// vouloir se placer avant d'écouter. S'il joue, il continue de là.
  Future<void> allerA(Event event, Duration cible) async {
    if (!await _armer(event)) return;
    await _lecteurPret.seek(cible);
    _position = cible;
    notifyListeners();
  }

  /// En cours d'écoute, un changement de vitesse doit s'entendre tout de suite.
  void changerVitesse(double vitesse) {
    if (_joue) unawaited(_lecteurPret.setPlaybackRate(vitesse));
  }

  /// Arrête l'écoute : on quitte la conversation.
  Future<void> arreter() async {
    if (_cle == null) return;
    _cle = null;
    _position = Duration.zero;
    notifyListeners();
    await _lecteur?.stop();
  }

  /// Pose un état sans passer par le lecteur, pour les tests.
  @visibleForTesting
  void etatPourTest({String? cle, bool joue = false, Duration? position}) {
    _cle = cle;
    _joue = joue;
    _position = position ?? Duration.zero;
    notifyListeners();
  }
}
