import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

typedef FichierEntrant = ({String nom, String? mime, Uint8List octets});

/// Écoute, dans toute la page, les fichiers collés (Ctrl+V) ou déposés.
///
/// Seul ce qui porte des fichiers est intercepté : un texte collé ou glissé
/// suit son chemin habituel. [surSurvol] suit un glisser de fichiers
/// au-dessus de la page, que le navigateur répète tant qu'il dure ;
/// [surFichiers] reçoit leur lecture, qui peut échouer (un dossier déposé).
/// Rend de quoi arrêter l'écoute.
void Function() ecouterFichiersEntrants({
  required void Function(Future<List<FichierEntrant>> fichiers) surFichiers,
  required void Function({required bool actif}) surSurvol,
}) {
  final abonnements = [
    web.EventStreamProviders.pasteEvent
        .forTarget(web.document, useCapture: true)
        .listen((e) {
      final fichiers = e.clipboardData?.files;
      if (fichiers == null || fichiers.length == 0) return;
      e.preventDefault();
      surFichiers(_lire(fichiers));
    }),
    web.EventStreamProviders.dragOverEvent
        .forTarget(web.document, useCapture: true)
        .listen((e) {
      final transfert = (e as web.DragEvent).dataTransfer;
      if (!_porteDesFichiers(transfert)) return;
      // Sans lui, le navigateur refuse le dépôt.
      e.preventDefault();
      transfert!.dropEffect = 'copy';
      surSurvol(actif: true);
    }),
    web.EventStreamProviders.dragLeaveEvent
        .forTarget(web.document, useCapture: true)
        .listen((e) {
      // Sortie de la fenêtre, ou Échap : plus rien au-dessus de la page.
      if ((e as web.DragEvent).relatedTarget == null) surSurvol(actif: false);
    }),
    web.EventStreamProviders.dropEvent
        .forTarget(web.document, useCapture: true)
        .listen((e) {
      final transfert = (e as web.DragEvent).dataTransfer;
      if (!_porteDesFichiers(transfert)) return;
      // Sans lui, le navigateur quitte Rempart pour afficher le fichier.
      e.preventDefault();
      surSurvol(actif: false);
      surFichiers(_lire(transfert!.files));
    }),
  ];
  return () {
    for (final abonnement in abonnements) {
      unawaited(abonnement.cancel());
    }
  };
}

bool _porteDesFichiers(web.DataTransfer? transfert) =>
    transfert?.types.toDart.any((type) => type.toDart == 'Files') ?? false;

/// Les fichiers sont relevés tout de suite : le navigateur vide la liste une
/// fois l'événement passé. Seule leur lecture attend.
Future<List<FichierEntrant>> _lire(web.FileList liste) {
  final fichiers = [
    for (var i = 0; i < liste.length; i++) liste.item(i)!,
  ];
  return Future.wait([
    for (final fichier in fichiers)
      fichier.arrayBuffer().toDart.then<FichierEntrant>(
            (octets) => (
              nom: fichier.name,
              mime: fichier.type.isEmpty ? null : fichier.type,
              octets: octets.toDart.asUint8List(),
            ),
            onError: (Object _) => throw _FichierIllisible(fichier.name),
          ),
  ]);
}

class _FichierIllisible implements Exception {
  const _FichierIllisible(this.nom);

  final String nom;

  @override
  String toString() =>
      "« $nom » ne peut pas être lu (un dossier ne s'envoie pas)";
}
