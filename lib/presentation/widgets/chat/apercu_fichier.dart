import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../../../core/plateforme.dart';
import '../../../core/telechargement.dart';
import '../../../data/models/matrix_extensions.dart';
import '../../../data/services/apercu_pdf.dart';

Future<Uint8List> _telecharger(matrix.Event event) async =>
    (await event.downloadAndDecryptAttachment()).bytes;

/// L'aperçu d'un fichier reçu (ni photo, ni vidéo, ni vocal), ouvert d'un
/// appui sur sa bulle.
///
/// Un appui ne faisait rien : on ne récupérait un fichier que par l'appui
/// long, que personne ne devine, et son « Enregistrer » ouvrait la feuille de
/// partage (relevé le 2026-10-22 avec une facture PDF envoyée par un agent).
/// Un PDF s'affiche ici page par page, sur Android ; ailleurs, et pour tout
/// autre fichier, une fiche dit ce que c'est. Enregistrer et Partager sont en
/// haut, comme dans la visionneuse.
class ApercuFichier extends StatefulWidget {
  const ApercuFichier({
    required this.event,
    required this.onEnregistrer,
    required this.onPartager,
    this.charger = _telecharger,
    this.pdf = const ApercuPdf(),
    super.key,
  });

  final matrix.Event event;
  final void Function(matrix.Event event) onEnregistrer;
  final void Function(matrix.Event event) onPartager;

  /// Les octets déchiffrés du fichier ; remplaçable pour les tests.
  final Future<Uint8List> Function(matrix.Event event) charger;

  final ApercuPdf pdf;

  @override
  State<ApercuFichier> createState() => _ApercuFichierState();
}

class _ApercuFichierState extends State<ApercuFichier> {
  late final Future<Uint8List> _octets = widget.charger(widget.event);

  /// Le PDF déposé pour le moteur d'Android, effacé à la fermeture.
  String? _chemin;

  /// Le nombre de pages, ou null quand il n'y a pas d'aperçu de pages.
  Future<int>? _pages;
  final _rendues = <int, Future<Uint8List>>{};

  final _zoom = TransformationController();
  bool _zoome = false;

  /// Doigts posés : à deux, c'est un zoom et le défilement se fige, sans
  /// quoi le premier doigt qui glisse fait défiler les pages avant que le
  /// second ne se pose (même piège que la visionneuse).
  int _doigts = 0;

  bool get _defilementFige => _zoome || _doigts >= 2;

  String get _nom => widget.event.fileInfo?.fileName ?? 'Fichier';

  bool get _estPdf =>
      widget.event.fileInfo?.mimeType == 'application/pdf' ||
      _nom.toLowerCase().endsWith('.pdf');

  @override
  void initState() {
    super.initState();
    if (_estPdf && widget.pdf.disponible) {
      _pages = _octets.then((octets) async {
        final chemin = _chemin = await widget.pdf.deposer(octets);
        return widget.pdf.nombreDePages(chemin);
      })
        // Un PDF illisible échoue avant que l'écran n'écoute (il attend
        // d'abord le téléchargement) : sans ceci, l'erreur partait comme non
        // gérée dans les rapports de plantage. L'écran la reçoit quand même.
        ..ignore();
    }
  }

  @override
  void dispose() {
    final chemin = _chemin;
    if (chemin != null) unawaited(widget.pdf.effacer(chemin));
    _zoom.dispose();
    super.dispose();
  }

  void _compterDoigts(int ecart) {
    final fige = _defilementFige;
    _doigts = math.max(0, _doigts + ecart);
    if (_defilementFige != fige) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF202124),
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        // Blanc imposé : le thème fixe la couleur des titres, et le
        // `foregroundColor` de la barre ne la remplace pas.
        title: Text(
          _nom,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Enregistrer',
            onPressed: () => widget.onEnregistrer(widget.event),
          ),
          IconButton(
            icon: Icon(Icons.adaptive.share),
            tooltip: 'Partager',
            onPressed: () => widget.onPartager(widget.event),
          ),
        ],
      ),
      body: FutureBuilder<Uint8List>(
        future: _octets,
        builder: (context, octets) {
          if (octets.hasError) {
            return _fiche(null, remarque: 'Téléchargement impossible.');
          }
          final donnees = octets.data;
          if (donnees == null) return const _Attente();
          final pages = _pages;
          if (pages == null) return _fiche(donnees);
          return FutureBuilder<int>(
            future: pages,
            builder: (context, nombre) {
              if (nombre.hasError) {
                return _fiche(
                  donnees,
                  remarque: 'Aperçu impossible : PDF protégé ou abîmé.',
                );
              }
              final total = nombre.data;
              if (total == null) return const _Attente();
              return _pagesPdf(total);
            },
          );
        },
      ),
    );
  }

  /// Ce qu'est le fichier, quand ses pages ne s'affichent pas.
  Widget _fiche(Uint8List? octets, {String? remarque}) {
    final taille = widget.event.fileInfo?.formattedSize ?? '';
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _estPdf ? Icons.picture_as_pdf : Icons.insert_drive_file,
              size: 72,
              color: Colors.white70,
            ),
            const SizedBox(height: 16),
            Text(
              _nom,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, color: Colors.white),
            ),
            if (taille.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(taille, style: const TextStyle(color: Colors.white60)),
            ],
            if (remarque != null) ...[
              const SizedBox(height: 12),
              Text(
                remarque,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60),
              ),
            ],
            const SizedBox(height: 24),
            // Le navigateur affiche un PDF tout seul : un onglet vaut mieux
            // qu'un aperçu de plus à maintenir.
            if (estWeb && _estPdf && octets != null) ...[
              FilledButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: const Text('Ouvrir dans un onglet'),
                onPressed: () =>
                    ouvrirDansUnOnglet(octets, mime: 'application/pdf'),
              ),
              const SizedBox(height: 12),
            ],
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Enregistrer'),
              onPressed: () => widget.onEnregistrer(widget.event),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pagesPdf(int total) {
    final chemin = _chemin!;
    // Plus fin que l'écran, pour que le zoom reste net, sans dépasser ce
    // qu'une image peut peser en mémoire.
    final largeur = math.min(
      2048,
      (MediaQuery.sizeOf(context).width *
              MediaQuery.devicePixelRatioOf(context) *
              1.5)
          .round(),
    );
    return Listener(
      onPointerDown: (_) => _compterDoigts(1),
      onPointerUp: (_) => _compterDoigts(-1),
      onPointerCancel: (_) => _compterDoigts(-1),
      child: InteractiveViewer(
        transformationController: _zoom,
        maxScale: 5,
        panEnabled: _zoome,
        onInteractionEnd: (_) {
          final zoome = _zoom.value.getMaxScaleOnAxis() > 1.01;
          if (zoome != _zoome) setState(() => _zoome = zoome);
        },
        child: ListView.separated(
          physics:
              _defilementFige ? const NeverScrollableScrollPhysics() : null,
          padding: const EdgeInsets.all(12),
          itemCount: total,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) => _PagePdf(
            rendu: _rendues.putIfAbsent(
              index,
              () => widget.pdf.page(chemin, index, largeur),
            ),
            libelle: 'Page ${index + 1} sur $total',
          ),
        ),
      ),
    );
  }
}

class _Attente extends StatelessWidget {
  const _Attente();

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator.adaptive());
}

/// Une page, à la place d'une feuille A4 tant qu'elle se rend : la liste ne
/// saute pas à chaque page qui arrive.
class _PagePdf extends StatelessWidget {
  const _PagePdf({required this.rendu, required this.libelle});

  final Future<Uint8List> rendu;
  final String libelle;

  static Widget _cadre({bool erreur = false}) => AspectRatio(
        aspectRatio: 1 / math.sqrt2,
        child: ColoredBox(
          color: Colors.white10,
          child: Center(
            child: erreur
                ? const Icon(Icons.broken_image, color: Colors.white54)
                : const CircularProgressIndicator.adaptive(),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: libelle,
      image: true,
      child: FutureBuilder<Uint8List>(
        future: rendu,
        builder: (context, page) {
          final octets = page.data;
          if (octets == null) return _cadre(erreur: page.hasError);
          // Jusqu'à la première image décodée, le cadre garde sa place : une
          // image pas encore décodée n'a pas de hauteur, et la page
          // s'aplatissait un instant avant de s'afficher.
          return Image.memory(
            octets,
            fit: BoxFit.fitWidth,
            frameBuilder: (context, image, trame, _) =>
                trame == null ? _cadre() : image,
          );
        },
      ),
    );
  }
}
