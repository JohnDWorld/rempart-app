import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Un enregistrement terminé, prêt à partir dans une conversation.
@immutable
class VocalEnregistre {
  const VocalEnregistre({
    required this.octets,
    required this.secondes,
    required this.mimeType,
    required this.nom,
    required this.formeOnde,
  });

  final Uint8List octets;
  final int secondes;
  final String mimeType;
  final String nom;

  /// Silhouette du son, entre 0 et 1024 (convention MSC3246), pour dessiner la
  /// barre du message plutôt qu'un trait plat.
  final List<int> formeOnde;
}

/// Enregistrement d'un message vocal.
///
/// Le format est de l'AAC-LC dans un conteneur M4A, et non de l'Opus qu'emploie
/// Element : Opus compresse mieux, mais iOS ne le lit pas nativement, et un
/// vocal qu'une moitié des appareils ne peut pas écouter ne vaut rien. L'AAC
/// se lit partout, y compris dans les autres clients Matrix.
///
/// Le débit est celui de la voix (32 kbit/s, mono) : environ 240 Ko la minute,
/// ce qui compte sur un envoi chiffré, où le média est téléversé en entier.
class EnregistreurVocal {
  EnregistreurVocal._();

  static final EnregistreurVocal instance = EnregistreurVocal._();

  final _enregistreur = AudioRecorder();
  String? _chemin;
  DateTime? _debut;

  /// Amplitudes relevées pendant l'enregistrement, en décibels.
  ///
  /// Mesurées ici et non recalculées à la lecture : décoder l'audio pour en
  /// tirer une silhouette demanderait de le décompresser en entier, sur le
  /// téléphone de celui qui écoute. Le micro, lui, donne la valeur pour rien.
  final _amplitudes = <double>[];
  StreamSubscription<Amplitude>? _mesure;

  /// L'enregistrement est-il possible ici ? Faux sur le web, où rien de tout
  /// ceci n'est branché (ni permission, ni fichier temporaire).
  bool get disponible => !kIsWeb;

  bool get enCours => _chemin != null;

  /// Temps écoulé depuis le début, pour le chronomètre affiché.
  Duration get ecoule =>
      _debut == null ? Duration.zero : DateTime.now().difference(_debut!);

  /// Demande le micro et commence à enregistrer.
  ///
  /// Rend faux si l'utilisateur refuse la permission : l'appelant le dit,
  /// plutôt que de laisser un bouton qui ne fait rien.
  Future<bool> demarrer() async {
    if (!disponible || enCours) return false;
    if (!await _enregistreur.hasPermission()) return false;

    final dossier = await getTemporaryDirectory();
    final chemin =
        '${dossier.path}/vocal_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _enregistreur.start(
      const RecordConfig(
        // Explicite bien que ce soit le defaut du paquet : ce format decide de
        // qui pourra ecouter le vocal, il ne doit pas changer dans notre dos a
        // la faveur d'une mise a jour.
        // ignore: avoid_redundant_argument_values
        encoder: AudioEncoder.aacLc,
        // Reglages volontairement ORDINAIRES. Un encodeur AAC materiel n'est
        // pas un logiciel : hors de ses combinaisons usuelles, il n'echoue pas
        // proprement, il ecrit quelques trames puis s'arrete. Le fichier
        // parait valide, se lit une seconde et se tait, alors que la duree
        // annoncee est la bonne. C'est ce qui est arrive avec 32 kbit/s a
        // 24 kHz laisses en STEREO (le mono avait saute) : 7 Ko pour un
        // message de plusieurs secondes.
        numChannels: 1,
        // Redondant avec le defaut, et garde tel quel : c'est en supprimant
        // une de ces lignes « inutiles » pour satisfaire le lint que le mono
        // a saute, et avec lui la lisibilite des vocaux.
        // ignore: avoid_redundant_argument_values
        sampleRate: 44100,
        bitRate: 64000,
        // MediaRecorder plutot que le chemin AudioRecord + MediaCodec.
        //
        // Le paquet le dit de ses deux implementations : l'avancee « unlocks
        // additionnal features », la seconde est « stability oriented », et
        // « legacy does NOT mean obsolete ». Or les fonctions avancees ne nous
        // servent a rien ici, tandis que la troncature nous a coute deux
        // allers-retours : un vocal de plusieurs secondes rendu en une, sans
        // la moindre erreur.
        //
        // Le format ne change pas (MPEG_4 + AAC-LC, donc le meme M4A), le
        // debit, la frequence et le mono sont respectes a l'identique, et
        // l'amplitude reste lue (getMaxAmplitude) : la silhouette survit.
        androidConfig: AndroidRecordConfig(
          useLegacy: true,
          // LE MICRO DU TELEPHONE, jamais celui d'un kit Bluetooth.
          //
          // Le defaut laisse Android router vers le peripherique connecte. En
          // voiture, la source devient alors le micro mains-libres, qui
          // n'echantillonne qu'a 8 kHz (la bande du telephone) : le vocal part
          // complet, de taille normale, mais sonne etouffe et metallique,
          // parce que le son d'origine ne porte que 4 kHz de bande passante.
          // Encoder a 44100 Hz n'y change rien, on ne restitue pas ce qui n'a
          // jamais ete capte.
          //
          // C'est le choix de WhatsApp, et il a un prix : le telephone pose
          // sur un support capte une voix plus lointaine que le micro du
          // volant. Une voix lointaine mais nette vaut mieux qu'une voix
          // proche et sourde, et surtout elle ne depend pas de ce qui est
          // connecte au moment ou l'on parle.
          audioSource: AndroidAudioSource.mic,
        ),
      ),
      path: chemin,
    );
    _chemin = chemin;
    _debut = DateTime.now();
    _amplitudes.clear();
    // Dix mesures par seconde : assez pour que la silhouette suive la voix,
    // assez peu pour qu'un message de deux minutes ne remplisse pas
    // l'evenement (on la reduit de toute facon a la fin).
    _mesure = _enregistreur
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen((a) => _amplitudes.add(a.current));
    return true;
  }

  /// Ramene les mesures a une silhouette courte, entre 0 et 1024.
  ///
  /// Les amplitudes viennent en decibels (negatifs, 0 etant le maximum). On
  /// coupe a -50 dB : en dessous c'est du silence, et le garder ecraserait
  /// toute la parole dans le haut du graphique.
  @visibleForTesting
  static List<int> silhouette(List<double> mesures, {int barres = 48}) {
    if (mesures.isEmpty) return const [];
    const plancher = -50.0;

    double niveau(double db) {
      if (!db.isFinite) return 0;
      final borne = db.clamp(plancher, 0.0);
      // Le decibel est logarithmique : sans cette conversion, un murmure et un
      // cri se ressembleraient.
      return pow(10, borne / 20).toDouble();
    }

    // Un vocal court donne moins de mesures que de barres : on garde alors ce
    // qu'on a plutot que d'etirer artificiellement.
    final n = min(barres, mesures.length);
    final valeurs = <double>[];
    for (var i = 0; i < n; i++) {
      final debut = (i * mesures.length / n).floor();
      final fin = (((i + 1) * mesures.length) / n).ceil().clamp(debut + 1, mesures.length);
      var maxi = 0.0;
      for (var j = debut; j < fin; j++) {
        final v = niveau(mesures[j]);
        if (v > maxi) maxi = v;
      }
      valeurs.add(maxi);
    }

    // Normalisation sur le plus fort : un enregistrement fait de loin doit
    // dessiner la meme silhouette qu'un autre fait de pres.
    //
    // Mais seulement s'il y a quelque chose a normaliser : sur un vocal
    // silencieux (micro coupe, personne ne parle), diviser par un plafond
    // minuscule remonte tout le bruit de fond au maximum et dessine une
    // silhouette pleine, exactement l'inverse de la verite. En dessous de
    // -40 dB, on declare le silence.
    final plafond = valeurs.reduce(max);
    if (plafond < 0.01) return List<int>.filled(n, 0);
    return [
      for (final v in valeurs) (v / plafond * 1024).round().clamp(0, 1024),
    ];
  }

  /// Arrête et rend l'enregistrement, ou null s'il n'y a rien d'exploitable.
  ///
  /// Le fichier temporaire est effacé dans tous les cas : les octets sont déjà
  /// en mémoire, et un dossier de cache qui se remplit de vocaux est un coût
  /// silencieux de plus.
  Future<VocalEnregistre?> arreter() async {
    if (!enCours) return null;
    final duree = ecoule;
    await _mesure?.cancel();
    _mesure = null;
    final forme = silhouette(List<double>.from(_amplitudes));
    _amplitudes.clear();
    final chemin = await _enregistreur.stop();
    _chemin = null;
    _debut = null;
    if (chemin == null) return null;

    final fichier = File(chemin);
    try {
      if (!fichier.existsSync()) return null;
      final octets = await fichier.readAsBytes();
      // Un appui involontaire produit un fichier d'en-tête sans son : l'envoyer
      // ne ferait qu'encombrer la conversation.
      if (octets.length < 1024 || duree.inMilliseconds < 700) return null;
      // Un encodeur qui abandonne en cours de route ne le dit pas : il rend un
      // fichier valide mais court, et seule l'ecoute revele la troncature. On
      // compare donc ce qu'on obtient a ce que le debit annonce, et on le
      // journalise. Le vocal part quand meme : incomplet vaut mieux que perdu.
      final attendu = 64000 ~/ 8 * duree.inSeconds;
      if (attendu > 0 && octets.length < attendu ~/ 2) {
        debugPrint(
          'Vocal: ${octets.length} octets pour ${duree.inSeconds} s, '
          "moitie moins qu'attendu ($attendu) : encodage probablement tronque",
        );
      }
      return VocalEnregistre(
        octets: octets,
        secondes: duree.inSeconds.clamp(1, 3600),
        mimeType: 'audio/mp4',
        nom: 'vocal_${DateTime.now().millisecondsSinceEpoch}.m4a',
        formeOnde: forme,
      );
    } finally {
      try {
        if (fichier.existsSync()) await fichier.delete();
      } catch (e) {
        debugPrint('Vocal: fichier temporaire non efface ($e)');
      }
    }
  }

  /// Abandonne l'enregistrement en cours, sans rien conserver.
  Future<void> annuler() async {
    if (!enCours) return;
    final chemin = _chemin;
    _chemin = null;
    _debut = null;
    await _mesure?.cancel();
    _mesure = null;
    _amplitudes.clear();
    try {
      await _enregistreur.cancel();
    } catch (e) {
      debugPrint('Vocal: annulation imparfaite ($e)');
    }
    if (chemin != null) {
      try {
        final fichier = File(chemin);
        if (fichier.existsSync()) await fichier.delete();
      } catch (e) {
        debugPrint('Vocal: fichier temporaire non efface ($e)');
      }
    }
  }
}
