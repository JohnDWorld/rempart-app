import 'dart:isolate';
import 'dart:ui';

import '../../core/plateforme.dart';

/// L'application principale est-elle vivante dans ce processus ?
///
/// Question vitale pour l'isolate d'arrière-plan : si l'application tourne
/// encore, sa base locale est **ouverte**, et y brancher un second client
/// Matrix fait se disputer le verrou SQLite. Le symptôme n'a alors plus rien à
/// voir avec sa cause : au retour dans l'application, la synchronisation part
/// en erreur, le bandeau « hors ligne » s'affiche et plus rien ne s'ouvre.
///
/// Un booléen partagé ne suffirait pas : chaque isolate a ses propres
/// variables, et le singleton de l'isolate d'arrière-plan naît toujours
/// « déconnecté ». `IsolateNameServer` est le seul registre commun aux
/// isolates d'un même processus, et il disparaît avec lui : quand Android tue
/// l'application, le nom n'est plus enregistré et l'arrière-plan retrouve le
/// droit d'ouvrir la base. C'est exactement la distinction voulue.
class PresenceIsolate {
  PresenceIsolate._();

  static const _nom = 'rempart_app_principale';

  static ReceivePort? _port;

  /// À appeler au démarrage de l'application : annonce qu'elle vit ici.
  ///
  /// Sans effet sur le web, où `IsolateNameServer` n'existe pas : ses méthodes
  /// y lèvent `UnimplementedError`, ce qui faisait planter le démarrage et
  /// n'affichait qu'une page blanche. Rien à annoncer de toute façon : le web
  /// n'a ni isolate d'arrière-plan ni notifications poussées, donc personne
  /// pour ouvrir une seconde base derrière nous.
  static void annoncer() {
    if (estWeb || _port != null) return;
    // Un enregistrement précédent peut subsister après un redémarrage à chaud
    // du moteur Flutter : le nom serait alors pris, et l'annonce ignorée.
    IsolateNameServer.removePortNameMapping(_nom);
    final port = _port = ReceivePort();
    IsolateNameServer.registerPortWithName(port.sendPort, _nom);
  }

  /// Vrai si l'application principale tourne dans ce processus.
  ///
  /// Faux sur le web, faute de registre : la question ne s'y pose pas, rien
  /// ne tourne en arrière-plan.
  static bool get applicationVivante =>
      !estWeb && IsolateNameServer.lookupPortByName(_nom) != null;
}
