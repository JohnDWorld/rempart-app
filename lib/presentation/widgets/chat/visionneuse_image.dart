import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../../../data/models/matrix_extensions.dart';

/// Affiche une image en plein écran, avec zoom et actions.
///
/// Une vignette contrainte à 75 % de la largeur de la bulle ne permet ni de
/// lire un texte photographié, ni de regarder un détail. Le zoom est donc le
/// coeur de cet écran ; enregistrer et partager sont proposés ici parce que
/// c'est le moment où on en a envie.
class VisionneuseImage extends StatelessWidget {
  const VisionneuseImage({
    required this.octets,
    required this.event,
    required this.onEnregistrer,
    required this.onPartager,
    super.key,
  });

  final Uint8List octets;
  final matrix.Event event;
  final VoidCallback onEnregistrer;
  final VoidCallback onPartager;

  @override
  Widget build(BuildContext context) {
    final legende = event.legendePieceJointe;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          event.senderDisplayName,
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Enregistrer',
            onPressed: () {
              Navigator.pop(context);
              onEnregistrer();
            },
          ),
          IconButton(
            icon: Icon(Icons.adaptive.share),
            tooltip: 'Partager',
            onPressed: () {
              Navigator.pop(context);
              onPartager();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              // Large amplitude : on ouvre souvent une photo pour lire ce
              // qu'elle contient, pas seulement pour la voir en grand.
              minScale: 1,
              maxScale: 6,
              child: Center(
                child: Image.memory(octets, fit: BoxFit.contain),
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
