import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../../../core/mouvement.dart';
import '../../../data/models/matrix_extensions.dart';
import '../../../data/services/cache_medias.dart';

/// Affiche des images en plein écran, avec zoom, défilement et actions.
///
/// Une vignette contrainte à 75 % de la largeur de la bulle ne permet ni de
/// lire un texte photographié, ni de regarder un détail. Le zoom est donc le
/// coeur de cet écran ; enregistrer et partager sont proposés ici parce que
/// c'est le moment où on en a envie.
///
/// Les photos d'un même envoi se parcourent d'un glissement : ouvrir un album
/// ne montrait que sa première photo, sans moyen d'aller aux suivantes.
class VisionneuseImage extends StatefulWidget {
  const VisionneuseImage({
    required this.images,
    required this.onEnregistrer,
    required this.onPartager,
    this.onEnregistrerTout,
    this.depart = 0,
    super.key,
  });

  /// Dans l'ordre de l'envoi.
  final List<matrix.Event> images;

  /// Indice de l'image ouverte en premier : celle qu'on a touchée.
  final int depart;

  final void Function(matrix.Event image) onEnregistrer;
  final void Function(matrix.Event image) onPartager;

  /// Toutes les photos de l'album d'un coup, proposé dès qu'il y en a deux.
  final void Function(List<matrix.Event> images)? onEnregistrerTout;

  @override
  State<VisionneuseImage> createState() => _VisionneuseImageState();
}

class _VisionneuseImageState extends State<VisionneuseImage> {
  late final _pages = PageController(initialPage: widget.depart);
  late int _courante = widget.depart;

  /// Image agrandie : le glissement la déplace au lieu de changer de page.
  bool _zoomee = false;

  /// Doigts posés sur l'écran. À deux, c'est un zoom, jamais un changement
  /// de page : en écartant les doigts, le premier qui glissait de quelques
  /// pixels était pris pour un défilement avant que le second ne se pose, et
  /// la photo filait vers sa voisine au lieu de s'agrandir (relevé le
  /// 2026-10-20, `test/visionneuse_zoom_test.dart`).
  int _doigts = 0;

  bool get _pagesFigees => _zoomee || _doigts >= 2;

  void _compterDoigts(int ecart) {
    final figees = _pagesFigees;
    _doigts = math.max(0, _doigts + ecart);
    if (_pagesFigees != figees) setState(() {});
  }

  /// Une souris ne fait pas glisser une page : Flutter réserve ce geste au
  /// doigt et au pavé tactile. Sur ordinateur, dans la version web, rien ne
  /// permettait donc de passer à la photo suivante (relevé le 2026-10-22).
  /// Des flèches s'affichent dès qu'une souris est branchée, et les touches
  /// ← → marchent partout.
  final _souris = RendererBinding.instance.mouseTracker;

  void _sourisChange() => setState(() {});

  @override
  void initState() {
    super.initState();
    _souris.addListener(_sourisChange);
  }

  @override
  void dispose() {
    _souris.removeListener(_sourisChange);
    _pages.dispose();
    super.dispose();
  }

  void _aller(int ecart) {
    final cible = _courante + ecart;
    if (cible < 0 || cible >= widget.images.length) return;
    final duree = dureeAnimation(context, const Duration(milliseconds: 250));
    // Sans mouvement demandé, la durée est nulle, ce qu'une animation refuse.
    if (duree == Duration.zero) return _pages.jumpToPage(cible);
    _pages.animateToPage(cible, duration: duree, curve: Curves.easeOutCubic);
  }

  Widget _fleche({required bool suivante}) => Align(
        alignment: suivante ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: IconButton.filled(
            tooltip: suivante ? 'Photo suivante' : 'Photo précédente',
            iconSize: 32,
            style: IconButton.styleFrom(
              backgroundColor: Colors.black54,
              foregroundColor: Colors.white,
            ),
            icon: Icon(suivante ? Icons.chevron_right : Icons.chevron_left),
            onPressed: () => _aller(suivante ? 1 : -1),
          ),
        ),
      );

  matrix.Event get _image => widget.images[_courante];

  @override
  Widget build(BuildContext context) {
    final legende = _image.legendePieceJointe;
    final total = widget.images.length;
    final fleches = _souris.mouseIsConnected;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _aller(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _aller(1),
      },
      child: Focus(
        autofocus: true,
        child: _page(context, legende, total, fleches),
      ),
    );
  }

  Widget _page(
    BuildContext context,
    String? legende,
    int total,
    bool fleches,
  ) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Jamais `senderDisplayName`, qui retombe sur l'identifiant.
            // Blanc imposé : le thème fixe la couleur des titres, et le
            // `foregroundColor` de la barre ne la remplace pas (le nom
            // s'affichait sombre sur noir).
            Text(
              _image.nomLisibleDeLExpediteur ?? 'Photo',
              style: const TextStyle(fontSize: 16, color: Colors.white),
            ),
            if (total > 1)
              Text(
                '${_courante + 1} sur $total',
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Enregistrer',
            onPressed: () {
              final image = _image;
              Navigator.pop(context);
              widget.onEnregistrer(image);
            },
          ),
          if (total > 1 && widget.onEnregistrerTout != null)
            IconButton(
              icon: const Icon(Icons.download_for_offline_outlined),
              tooltip: 'Tout enregistrer ($total)',
              onPressed: () {
                final images = widget.images;
                Navigator.pop(context);
                widget.onEnregistrerTout!(images);
              },
            ),
          IconButton(
            icon: Icon(Icons.adaptive.share),
            tooltip: 'Partager',
            onPressed: () {
              final image = _image;
              Navigator.pop(context);
              widget.onPartager(image);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Listener(
                  onPointerDown: (_) => _compterDoigts(1),
                  onPointerUp: (_) => _compterDoigts(-1),
                  onPointerCancel: (_) => _compterDoigts(-1),
                  child: PageView.builder(
                    controller: _pages,
                    physics: _pagesFigees
                        ? const NeverScrollableScrollPhysics()
                        : null,
                    itemCount: total,
                    onPageChanged: (index) => setState(() {
                      _courante = index;
                      _zoomee = false;
                    }),
                    itemBuilder: (context, index) => _PageImage(
                      key: ValueKey(cleMedia(widget.images[index])),
                      image: widget.images[index],
                      onZoom: (zoomee) {
                        if (zoomee != _zoomee) setState(() => _zoomee = zoomee);
                      },
                    ),
                  ),
                ),
                if (fleches && _courante > 0) _fleche(suivante: false),
                if (fleches && _courante < total - 1) _fleche(suivante: true),
              ],
            ),
          ),
          if (legende != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Text(
                legende,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

/// Une image de la visionneuse, en pleine résolution.
class _PageImage extends StatefulWidget {
  const _PageImage({required this.image, required this.onZoom, super.key});

  final matrix.Event image;
  final ValueChanged<bool> onZoom;

  @override
  State<_PageImage> createState() => _PageImageState();
}

class _PageImageState extends State<_PageImage>
    with SingleTickerProviderStateMixin {
  final _transformation = TransformationController();

  /// Le double appui agrandit là où l'on a touché, ou rend la taille : sans
  /// lui, il fallait écarter deux doigts pour lire le moindre détail.
  late final AnimationController _animation;
  Matrix4Tween _trajet = Matrix4Tween();
  Offset _pointTouche = Offset.zero;
  static const _echelleDoubleAppui = 2.5;

  bool get _agrandie => _transformation.value.getMaxScaleOnAxis() > 1.01;

  void _doubleAppui() {
    final agrandir = !_agrandie;
    final point = _pointTouche;
    const e = _echelleDoubleAppui;
    _trajet = Matrix4Tween(
      begin: _transformation.value,
      // Agrandir autour du point touché : il reste sous le doigt.
      end: agrandir
          ? (Matrix4.diagonal3Values(e, e, 1)
            ..setTranslationRaw(-point.dx * (e - 1), -point.dy * (e - 1), 0))
          : Matrix4.identity(),
    );
    _animation
      ..duration = dureeAnimation(context, const Duration(milliseconds: 220))
      ..forward(from: 0);
    widget.onZoom(agrandir);
  }

  @override
  void initState() {
    super.initState();
    // Pas paresseux : créé pour la première fois dans `dispose`, quand on a
    // glissé vers une autre photo sans double appui, il demandait son
    // horloge à une page déjà détachée et levait une erreur.
    _animation = AnimationController(vsync: this)
      ..addListener(() => _transformation.value = _trajet.evaluate(_animation));
  }

  // Déjà en mémoire la plupart du temps : la vignette l'a chargée.
  late final _media = CacheMedias.instance.deja(cleMedia(widget.image));
  late final Future<MediaCharge> _chargement =
      _media != null ? Future.value(_media) : chargerImage(widget.image);

  @override
  void dispose() {
    _animation.dispose();
    _transformation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MediaCharge>(
      future: _chargement,
      initialData: _media,
      builder: (context, etat) {
        final media = etat.data;
        if (media == null) {
          return Center(
            child: etat.hasError
                ? const Icon(
                    Icons.broken_image,
                    size: 48,
                    color: Colors.white54,
                  )
                : const CircularProgressIndicator.adaptive(),
          );
        }
        return GestureDetector(
          onDoubleTapDown: (details) => _pointTouche = details.localPosition,
          onDoubleTap: _doubleAppui,
          child: InteractiveViewer(
            transformationController: _transformation,
            // Large amplitude : on ouvre souvent une photo pour lire ce
            // qu'elle contient, pas seulement pour la voir en grand.
            minScale: 1,
            maxScale: 6,
            onInteractionStart: (_) => _animation.stop(),
            onInteractionEnd: (_) => widget.onZoom(_agrandie),
            child:
                Center(child: Image.memory(media.octets, fit: BoxFit.contain)),
          ),
        );
      },
    );
  }
}
