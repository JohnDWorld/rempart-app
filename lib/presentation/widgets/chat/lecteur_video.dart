import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:video_player/video_player.dart';

import '../../../data/models/matrix_extensions.dart';
import 'source_video_io.dart'
    if (dart.library.js_interop) 'source_video_web.dart';

/// Lecture d'une vidéo reçue ou envoyée, en plein écran.
///
/// Il fallait auparavant l'enregistrer pour la regarder, hors de Rempart.
/// Dans un salon chiffré, l'adresse du média ne rend que du chiffré : la
/// vidéo est téléchargée et déchiffrée ici, avec la progression, puis confiée
/// au lecteur (voir `ouvrirVideo`).
class LecteurVideo extends StatefulWidget {
  const LecteurVideo({
    required this.video,
    required this.onEnregistrer,
    required this.onPartager,
    super.key,
  });

  final matrix.Event video;
  final void Function(matrix.Event video) onEnregistrer;
  final void Function(matrix.Event video) onPartager;

  @override
  State<LecteurVideo> createState() => _LecteurVideoState();
}

class _LecteurVideoState extends State<LecteurVideo> {
  VideoPlayerController? _lecteur;
  Future<void> Function()? _liberer;
  int _recus = 0;
  bool _echec = false;

  /// Commandes visibles : elles s'effacent pendant la lecture et reviennent
  /// au toucher, comme dans toute visionneuse de vidéos.
  bool _commandes = true;
  Timer? _masquage;

  int? get _taille => widget.video.fileInfo?.size;

  @override
  void initState() {
    super.initState();
    unawaited(_charger());
  }

  Future<void> _charger() async {
    try {
      final fichier = await widget.video.downloadAndDecryptAttachment(
        onDownloadProgress: (recus) {
          if (mounted) setState(() => _recus = recus);
        },
      );
      final mime = widget.video.fileInfo?.mimeType ?? 'video/mp4';
      final (lecteur, liberer) = await ouvrirVideo(
        fichier.bytes,
        nom: '${widget.video.eventId.hashCode.abs()}',
        mime: mime,
      );
      _liberer = liberer;
      if (!mounted) {
        await liberer();
        return;
      }
      await lecteur.initialize();
      if (!mounted) {
        await lecteur.dispose();
        await liberer();
        return;
      }
      lecteur.addListener(_surLecture);
      setState(() => _lecteur = lecteur);
      await lecteur.play();
      _planifierMasquage();
    } catch (e) {
      debugPrint('LecteurVideo : lecture impossible ($e)');
      if (mounted) setState(() => _echec = true);
    }
  }

  @override
  void dispose() {
    _masquage?.cancel();
    final lecteur = _lecteur;
    lecteur?.removeListener(_surLecture);
    unawaited(lecteur?.dispose());
    // La copie en clair part avec le lecteur.
    unawaited(_liberer?.call());
    super.dispose();
  }

  void _surLecture() {
    if (!mounted) return;
    final etat = _lecteur!.value;
    // Arrivée au bout : les commandes reviennent, sans quoi la vidéo finie
    // resterait figée sur sa dernière image, sans bouton pour la relancer.
    if (!etat.isPlaying && etat.position >= etat.duration) _commandes = true;
    setState(() {});
  }

  void _planifierMasquage() {
    _masquage?.cancel();
    _masquage = Timer(const Duration(seconds: 3), () {
      if (mounted && (_lecteur?.value.isPlaying ?? false)) {
        setState(() => _commandes = false);
      }
    });
  }

  void _basculerLecture() {
    final lecteur = _lecteur;
    if (lecteur == null) return;
    if (lecteur.value.isPlaying) {
      unawaited(lecteur.pause());
    } else {
      // Arrivée au bout, `play` repart lui-même du début.
      unawaited(lecteur.play());
      _planifierMasquage();
    }
    setState(() => _commandes = true);
  }

  void _agir(void Function(matrix.Event) action) {
    Navigator.pop(context);
    action(widget.video);
  }

  @override
  Widget build(BuildContext context) {
    final legende = widget.video.legendePieceJointe;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        // Blanc imposé : le thème fixe la couleur des titres (voir la
        // visionneuse d'images).
        title: Text(
          widget.video.nomLisibleDeLExpediteur ?? 'Vidéo',
          style: const TextStyle(fontSize: 16, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Enregistrer',
            onPressed: () => _agir(widget.onEnregistrer),
          ),
          IconButton(
            icon: Icon(Icons.adaptive.share),
            tooltip: 'Partager',
            onPressed: () => _agir(widget.onPartager),
          ),
        ],
      ),
      // Commandes posées PAR-DESSUS la vidéo : prises dans la colonne, elles
      // la faisaient sauter à chaque fois qu'elles s'effaçaient.
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _video()),
            if (_commandes && (_lecteur != null || legende != null))
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black54],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (legende != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                          child: Text(
                            legende,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      if (_lecteur != null) _barre(_lecteur!),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _video() {
    if (_echec) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_outlined, color: Colors.white54, size: 48),
            SizedBox(height: 12),
            Text(
              'Lecture impossible. « Enregistrer » la garde dans la galerie.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }
    final lecteur = _lecteur;
    if (lecteur == null) {
      final taille = _taille;
      final avancement = taille == null || taille == 0 ? null : _recus / taille;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              value: avancement,
              color: Colors.white,
            ),
            const SizedBox(height: 16),
            Text(
              taille == null
                  ? 'Téléchargement…'
                  : 'Téléchargement… ${_mo(_recus)} sur ${_mo(taille)}',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() => _commandes = !_commandes);
        if (_commandes) _planifierMasquage();
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: lecteur.value.aspectRatio,
            child: VideoPlayer(lecteur),
          ),
          if (_commandes)
            IconButton.filled(
              iconSize: 44,
              style: IconButton.styleFrom(
                backgroundColor: Colors.black45,
                foregroundColor: Colors.white,
              ),
              tooltip: lecteur.value.isPlaying ? 'Pause' : 'Lire',
              onPressed: _basculerLecture,
              icon: Icon(
                lecteur.value.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
            ),
        ],
      ),
    );
  }

  Widget _barre(VideoPlayerController lecteur) {
    const style = TextStyle(color: Colors.white, fontSize: 13);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          Text(_mmss(lecteur.value.position), style: style),
          const SizedBox(width: 12),
          Expanded(
            child: VideoProgressIndicator(
              lecteur,
              allowScrubbing: true,
              padding: const EdgeInsets.symmetric(vertical: 12),
              colors: VideoProgressColors(
                playedColor: Theme.of(context).colorScheme.primary,
                bufferedColor: Colors.white24,
                backgroundColor: Colors.white12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(_mmss(lecteur.value.duration), style: style),
        ],
      ),
    );
  }
}

String _mmss(Duration d) {
  final m = d.inMinutes.toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

String _mo(int octets) => '${(octets / (1024 * 1024)).toStringAsFixed(1)} Mo';
