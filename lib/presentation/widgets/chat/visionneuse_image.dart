import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;

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
    this.depart = 0,
    super.key,
  });

  /// Dans l'ordre de l'envoi.
  final List<matrix.Event> images;

  /// Indice de l'image ouverte en premier : celle qu'on a touchée.
  final int depart;

  final void Function(matrix.Event image) onEnregistrer;
  final void Function(matrix.Event image) onPartager;

  @override
  State<VisionneuseImage> createState() => _VisionneuseImageState();
}

class _VisionneuseImageState extends State<VisionneuseImage> {
  late final _pages = PageController(initialPage: widget.depart);
  late int _courante = widget.depart;

  /// Image agrandie : le glissement la déplace au lieu de changer de page.
  bool _zoomee = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  matrix.Event get _image => widget.images[_courante];

  @override
  Widget build(BuildContext context) {
    final legende = _image.legendePieceJointe;
    final total = widget.images.length;

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
            child: PageView.builder(
              controller: _pages,
              physics: _zoomee ? const NeverScrollableScrollPhysics() : null,
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

class _PageImageState extends State<_PageImage> {
  final _transformation = TransformationController();

  // Déjà en mémoire la plupart du temps : la vignette l'a chargée.
  late final _media = CacheMedias.instance.deja(cleMedia(widget.image));
  late final Future<MediaCharge> _chargement =
      _media != null ? Future.value(_media) : chargerImage(widget.image);

  @override
  void dispose() {
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
        return InteractiveViewer(
          transformationController: _transformation,
          // Large amplitude : on ouvre souvent une photo pour lire ce qu'elle
          // contient, pas seulement pour la voir en grand.
          minScale: 1,
          maxScale: 6,
          onInteractionEnd: (_) => widget.onZoom(
            _transformation.value.getMaxScaleOnAxis() > 1.01,
          ),
          child: Center(child: Image.memory(media.octets, fit: BoxFit.contain)),
        );
      },
    );
  }
}
