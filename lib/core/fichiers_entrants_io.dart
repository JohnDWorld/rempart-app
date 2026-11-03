import 'dart:typed_data';

typedef FichierEntrant = ({String nom, String? mime, Uint8List octets});

/// Hors navigateur, rien n'arrive par là : une pièce jointe passe par le
/// bouton ou par le partage du système.
void Function() ecouterFichiersEntrants({
  required void Function(Future<List<FichierEntrant>> fichiers) surFichiers,
  required void Function({required bool actif}) surSurvol,
}) =>
    () {};
