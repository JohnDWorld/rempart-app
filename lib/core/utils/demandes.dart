import 'apercu_notification.dart';

/// L'auteur d'une invitation est-il quelqu'un que l'on connaît déjà ?
///
/// Rempart n'a pas de carnet de contacts, et c'est voulu : aucun répertoire ne
/// part au serveur. « Connu » ne peut donc venir que de ce que le compte sait
/// déjà : ses tête-à-tête (`m.direct`, synchronisés entre ses appareils, tenus
/// à jour à chaque conversation créée ou acceptée) et ses propres bots. Un
/// groupe partagé ne suffit pas : il ferait de tout membre d'un grand groupe
/// un « connu ».
bool inviteurConnu(
  String inviteur, {
  required Map<String, List<String>> tetesATetes,
  required Set<String> mesBots,
}) =>
    tetesATetes.containsKey(inviteur) || mesBots.contains(inviteur);

/// Notification d'une demande. Jamais le contenu : un message chiffré ne se
/// lit qu'une fois le salon rejoint, et c'est justement ce qu'on n'a pas fait.
ApercuNotification apercuDemande({String? nomInviteur, String? nomGroupe}) {
  final qui = nomInviteur ?? "Quelqu'un";
  if (nomGroupe != null) {
    return ApercuNotification(
      titre: 'Invitation dans un groupe',
      corps: '$qui vous invite dans « $nomGroupe »',
    );
  }
  return ApercuNotification(
    titre: 'Demande de message',
    corps: '$qui souhaite vous écrire',
  );
}

/// Libellé du bandeau en tête de la liste des conversations.
String libelleDemandes(int nombre) =>
    nombre == 1 ? '1 demande de message' : '$nombre demandes de message';
