import 'package:matrix/matrix.dart' as matrix;

import '../../data/models/matrix_extensions.dart';

/// Regroupe les médias d'un même envoi, en laissant le reste tel quel.
///
/// Rend une liste de groupes : un seul événement pour un message ordinaire,
/// plusieurs pour des photos parties ensemble. L'ordre de la liste d'entrée est
/// conservé, y compris celui, inversé, du fil de discussion.
///
/// Seuls les événements **voisins** sont réunis : un message glissé entre deux
/// photos coupe le groupe. Sans quoi une grille rassemblerait des images que
/// l'on n'a pas vues côte à côte, et l'ordre du fil deviendrait faux.
List<List<matrix.Event>> grouperParAlbum(List<matrix.Event> evenements) {
  final groupes = <List<matrix.Event>>[];
  for (final evenement in evenements) {
    final album = evenement.albumId;
    final precedent = groupes.isEmpty ? null : groupes.last;

    final memeAlbum = album != null &&
        precedent != null &&
        precedent.first.albumId == album &&
        // Même expéditeur : deux personnes ne partagent pas un album, et un
        // identifiant qui se répéterait par accident ne doit pas les mêler.
        precedent.first.senderId == evenement.senderId;

    if (memeAlbum) {
      precedent.add(evenement);
    } else {
      groupes.add([evenement]);
    }
  }
  return groupes;
}
