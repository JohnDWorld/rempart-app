import 'package:matrix/matrix.dart';

/// Ce qu'un contact fait dans une conversation, en ce moment.
///
/// Matrix sait dire « écrit » (`m.typing`), pas « enregistre un vocal ». Ce
/// second état passe donc par un signal à nous, envoyé directement aux
/// appareils des membres (message d'appareil à appareil, non chiffré : le
/// serveur voit « Léa enregistre dans ce salon », comme il voit déjà « Léa
/// écrit »). Les autres clients Matrix l'ignorent.
const typeSignalEnregistrement = 'fr.rempart.enregistrement';

/// L'émetteur répète le signal à cet intervalle tant qu'il enregistre.
const repetitionSignalEnregistrement = Duration(seconds: 15);

/// Sans nouvelles depuis ce délai, l'indicateur s'éteint : une application
/// qui plante en plein enregistrement ne doit pas le laisser allumé.
const vieSignalEnregistrement = Duration(seconds: 30);

Map<String, Object> contenuSignalEnregistrement(
  String roomId, {
  required bool actif,
  required DateTime maintenant,
}) =>
    {
      'room_id': roomId,
      'actif': actif,
      'ts': maintenant.millisecondsSinceEpoch,
    };

/// L'état que porte [evenement] pour [roomId], ou `null` s'il ne compte pas.
///
/// Un signal ancien est écarté : le SDK garde en file un envoi échoué et le
/// rejoue plus tard, et un téléphone resté hors ligne reçoit d'un bloc ce qui
/// l'attendait. Sans l'heure, l'un ou l'autre ferait « enregistrer » un
/// contact qui a fini depuis longtemps.
bool? etatSignalEnregistrement(
  ToDeviceEvent evenement, {
  required String roomId,
  required String? moi,
  required DateTime maintenant,
}) {
  if (evenement.type != typeSignalEnregistrement) return null;
  if (evenement.sender == moi) return null;
  final contenu = evenement.content;
  if (contenu['room_id'] != roomId) return null;
  final actif = contenu['actif'];
  final ts = contenu['ts'];
  if (actif is! bool || ts is! int) return null;
  final age = maintenant.difference(DateTime.fromMillisecondsSinceEpoch(ts));
  if (age > vieSignalEnregistrement) return null;
  return actif;
}

/// Sous-titre de l'en-tête pendant qu'un ou plusieurs membres écrivent, ou
/// enregistrent un vocal.
///
/// En tête-à-tête, nommer l'autre redirait l'en-tête ; dans un groupe, le nom
/// est justement l'information utile.
String libelleActivite({
  required bool direct,
  required List<String> noms,
  required bool enregistre,
}) {
  if (direct) {
    return enregistre ? 'enregistre un vocal...' : "en train d'écrire...";
  }
  if (noms.length == 1) {
    return enregistre
        ? '${noms.first} enregistre un vocal...'
        : '${noms.first} écrit...';
  }
  if (noms.length == 2) {
    return enregistre
        ? '${noms[0]} et ${noms[1]} enregistrent un vocal...'
        : '${noms[0]} et ${noms[1]} écrivent...';
  }
  return enregistre
      ? 'plusieurs personnes enregistrent un vocal...'
      : 'plusieurs personnes écrivent...';
}
