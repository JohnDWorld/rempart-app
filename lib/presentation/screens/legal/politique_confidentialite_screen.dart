import 'package:flutter/material.dart';

import 'document_legal.dart';

/// Politique de confidentialité de Rempart Messenger.
///
/// Décrit ce que le service collecte, ce qu'il ne peut pas voir, à qui
/// les données sont transmises et combien de temps elles sont gardées.
///
/// Texte rédigé à partir des informations fournies par l'éditeur et de
/// la configuration réelle des serveurs. Une relecture juridique reste
/// conseillée avant publication.
class PolitiqueConfidentialiteScreen extends StatelessWidget {
  const PolitiqueConfidentialiteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DocumentLegal(
      titre: 'Politique de confidentialité',
      miseAJour: '22 août 2026',
      sections: [
        SectionLegale('Responsable de traitement', [
          'Jonathan Demory, exerçant sous le nom commercial The Van Codeur, entrepreneur individuel, SIRET 93424185200011, 60 rue Jules Legrand, 56100 Lorient, France.',
          'Pour toute question relative à vos données, ou pour exercer vos droits : j.demory@proton.me.',
          "Aucun délégué à la protection des données n'est désigné : la structure n'y est pas tenue.",
        ]),
        SectionLegale('Ce que le service ne voit pas', [
          "Les conversations entre utilisateurs sont chiffrées de bout en bout. Le contenu des messages, les pièces jointes et les photos échangées ne sont lisibles que sur les appareils des participants. Ni l'éditeur, ni l'hébergeur, ni un tiers ne peuvent en prendre connaissance, y compris sur réquisition : les clés ne quittent pas les appareils.",
          "Cette impossibilité est technique et non contractuelle : elle ne dépend pas d'une promesse mais de la façon dont le service est construit.",
        ]),
        SectionLegale('Données collectées', [
          "Compte : adresse électronique et mot de passe, ce dernier stocké sous forme d'empreinte, jamais en clair.",
          'Profil : nom affiché, photo et biographie, si vous les renseignez. Ces informations sont visibles de vos contacts.',
          'Activité : date de dernière connexion et indicateur de présence.',
          "Sessions : pour chaque appareil connecté, un identifiant de session, la date de dernière activité et l'adresse IP utilisée. Ces informations vous sont montrées dans l'écran « Appareils connectés ».",
          "Messages : conservés chiffrés sur le serveur pour permettre leur remise, y compris à un appareil hors ligne. Le serveur en connaît la date, l'expéditeur et la conversation, mais pas le contenu.",
          "Notifications : un jeton d'appareil, nécessaire pour vous joindre lorsque l'application est fermée.",
          "Rapports de plantage : lorsque l'application rencontre une erreur, une trace technique est envoyée avec le modèle de l'appareil et la version du système. Ces rapports ne contiennent aucun contenu de message, aucune capture d'écran et aucun identifiant de compte.",
          "Le service ne pratique aucune mesure d'audience et n'embarque aucun traceur publicitaire.",
        ]),
        SectionLegale('Conversations avec un bot', [
          'Les conversations avec un bot ne sont pas chiffrées de bout en bout : un bot ne détient aucune clé. Leur contenu est donc lisible par le serveur.',
          "Lorsque vous écrivez au bot d'un autre utilisateur, votre message est transmis à l'agent que cette personne fait tourner, en dehors de Rempart. L'éditeur n'a aucun contrôle sur cet agent ni sur ce qu'il fait des messages reçus. L'application signale ces conversations par un bandeau explicite.",
        ]),
        SectionLegale('Bases légales', [
          "L'exécution du contrat, pour tout ce qui est nécessaire au fonctionnement de la messagerie : compte, profil, remise des messages, notifications.",
          "L'intérêt légitime, pour la sécurité du service et la correction des anomalies : journaux techniques et rapports de plantage.",
        ]),
        SectionLegale('Destinataires', [
          'OVH SAS (France), hébergeur des serveurs.',
          "Google (Firebase Cloud Messaging), pour l'acheminement des notifications sur Android. Le service est configuré pour ne transmettre aucun contenu : la notification poussée ne porte qu'un identifiant d'événement, et le texte est ajouté par l'application elle-même, sur votre appareil.",
          'Apple (Apple Push Notification service), même rôle sur iPhone et dans les mêmes conditions.',
          "Vous pouvez remplacer ces deux passerelles par UnifiedPush dans les réglages, et ainsi ne dépendre d'aucune des deux.",
          'Les rapports de plantage sont collectés par une instance auto-hébergée sur les serveurs du service : aucun tiers ne les reçoit.',
          "Aucune donnée n'est vendue, louée ni transmise à des fins publicitaires.",
        ]),
        SectionLegale('Durées de conservation', [
          "Compte et profil : jusqu'à la suppression du compte.",
          "Messages chiffrés : conservés sur le serveur le temps de leur remise, puis dans l'historique de la conversation tant que celle-ci existe.",
          'Conversations quittées par tous leurs membres : effacées automatiquement au bout de 7 jours.',
          "Médias provenant d'autres serveurs : 7 jours, ce cache étant reconstitué au besoin.",
          'Adresses IP et informations de session : 28 jours.',
          'Rapports de plantage : 90 jours.',
          "Journaux techniques des serveurs : conservés pour le seul diagnostic des incidents, sans archivage ni exploitation à d'autres fins.",
        ]),
        SectionLegale('Suppression du compte', [
          "Vous pouvez supprimer votre compte depuis l'application, dans les réglages. Vos identifiants et votre profil sont alors effacés.",
          'Les messages déjà reçus par vos correspondants restent sur leurs appareils : le service ne peut pas les y effacer.',
        ]),
        SectionLegale('Vos droits', [
          "Vous disposez d'un droit d'accès, de rectification, d'effacement, de limitation, d'opposition et de portabilité sur vos données. Écrivez à j.demory@proton.me ; une réponse vous sera apportée dans un délai d'un mois.",
          "Le chiffrement de bout en bout borne ce qui peut vous être communiqué : le contenu de vos messages n'étant pas accessible au service, il ne peut pas figurer dans une réponse à une demande d'accès. Il se trouve déjà sur vos appareils.",
          'Vous pouvez introduire une réclamation auprès de la CNIL, 3 place de Fontenoy, TSA 80715, 75334 Paris Cedex 07, ou sur cnil.fr.',
        ]),
        SectionLegale('Sécurité', [
          'Les échanges avec les serveurs sont chiffrés en transit. Les messages entre utilisateurs le sont de bout en bout, et les clés de déchiffrement sont conservées sur vos appareils, protégées par votre mot de passe.',
          'Les serveurs sont situés en France, chez OVH.',
        ]),
        SectionLegale('Mineurs', [
          "Le service n'est pas destiné aux personnes de moins de 15 ans, âge de la majorité numérique en France.",
        ]),
        SectionLegale('Modifications', [
          "Cette politique peut évoluer. La date de mise à jour figure en tête du document, et les changements notables vous seront signalés dans l'application.",
        ]),
      ],
    );
  }
}
