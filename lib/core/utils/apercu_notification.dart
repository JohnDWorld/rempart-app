import 'secret_message.dart';

/// Titre et corps d'une notification de message.
class ApercuNotification {
  const ApercuNotification({required this.titre, required this.corps});

  final String titre;
  final String corps;
}

/// Compose ce qui s'affichera dans le bandeau de notification.
///
/// Fonction pure, et c'est voulu : les deux chemins qui produisent une
/// notification (la boucle de sync quand l'application tourne, l'isolate
/// d'arrière-plan quand elle est fermée) doivent dire exactement la même
/// chose. Deux compositions séparées divergeraient à la première retouche.
///
/// [nomExpediteur] et [nomRoom] sont déjà résolus par l'appelant, et valent
/// null si rien de lisible n'a pu l'être. **Aucun identifiant technique ne doit
/// y arriver** : un mxid ou un localpart engendré ne dit rien à personne, et
/// l'écran verrouillé est le pire endroit pour en afficher un.
///
/// [nomRoom] n'est renseigné que pour un groupe : dans un tête-à-tête, le nom
/// de la conversation est celui du contact, qui est déjà le titre.
ApercuNotification composerApercu({
  required String texte,
  String? nomExpediteur,
  String? nomRoom,
}) {
  // Un code ou un mot de passe n'a rien à faire sur un écran verrouillé,
  // lisible de qui passe derrière. L'expéditeur reste annoncé : c'est le
  // contenu qui est sensible, pas le fait d'avoir reçu un message.
  final corps = ressembleAUnSecret(texte) ? 'Message masqué' : texte;

  // Dans un groupe, le titre est le groupe, donc l'auteur doit apparaître dans
  // le corps : sans lui, trois messages de trois personnes sont indiscernables.
  if (nomRoom != null) {
    return ApercuNotification(
      titre: nomRoom,
      corps: nomExpediteur == null ? corps : '$nomExpediteur : $corps',
    );
  }

  return ApercuNotification(
    titre: nomExpediteur ?? 'Rempart',
    corps: corps,
  );
}
