import 'package:flutter/material.dart';

import 'document_legal.dart';

/// Conditions d'utilisation de Rempart Messenger.
///
/// Elles incluent les mentions légales : pour une application, tout
/// regrouper dans un document consultable évite d'en multiplier les
/// entrées dans les réglages.
///
/// Texte rédigé à partir des informations fournies par l'éditeur. Une
/// relecture juridique reste conseillée avant publication : ce document
/// engage.
class ConditionsUtilisationScreen extends StatelessWidget {
  const ConditionsUtilisationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DocumentLegal(
      titre: "Conditions d'utilisation",
      miseAJour: '22 août 2026',
      sections: [
        SectionLegale('Éditeur du service', [
          'Rempart Messenger est édité par Jonathan Demory, exerçant sous le nom commercial The Van Codeur, entrepreneur individuel immatriculé sous le numéro SIRET 93424185200011.',
          'Adresse : 60 rue Jules Legrand, 56100 Lorient, France.',
          'Téléphone : 06 17 32 86 98.',
          'Adresse électronique : j.demory@proton.me.',
          'Directeur de la publication : Jonathan Demory.',
        ]),
        SectionLegale('Hébergement', [
          'Les serveurs de Rempart Messenger sont hébergés par OVH SAS, 2 rue Kellermann, 59100 Roubaix, France.',
        ]),
        SectionLegale('Objet du service', [
          "Rempart Messenger est une messagerie instantanée. Les conversations entre utilisateurs sont chiffrées de bout en bout : leur contenu n'est lisible que sur les appareils des participants, jamais par l'éditeur ni par l'hébergeur.",
          "L'application repose sur le protocole ouvert Matrix.",
        ]),
        SectionLegale('Accès au service', [
          "L'inscription est réservée aux personnes âgées d'au moins 15 ans, âge de la majorité numérique en France. En créant un compte, vous déclarez avoir atteint cet âge.",
          "L'accès nécessite une adresse électronique valide et une connexion à Internet.",
        ]),
        SectionLegale('Votre compte et vos clés', [
          'Vous êtes responsable de la confidentialité de votre mot de passe.',
          "Point important, propre au chiffrement de bout en bout : votre mot de passe protège aussi vos clés de déchiffrement. Le perdre sans disposer de votre clé de récupération vous prive de vos anciens messages. Personne, éditeur compris, ne peut les restaurer à votre place : ce n'est pas un défaut du service, mais la conséquence directe de sa promesse.",
          "Conservez la clé de récupération qui vous est présentée à l'inscription et à chaque changement de mot de passe.",
        ]),
        SectionLegale('Usages interdits', [
          "Il vous est interdit d'utiliser le service pour diffuser des contenus illicites, harceler autrui, usurper une identité, envoyer des messages non sollicités en masse, ou porter atteinte au fonctionnement du service et de ses serveurs.",
          "Le chiffrement empêche l'éditeur de prendre connaissance du contenu des conversations : la modération repose donc sur les signalements et sur les mesures applicables aux comptes, non sur une surveillance des échanges.",
        ]),
        SectionLegale('Bots et agents externes', [
          "Le service permet de créer des bots pilotés par un agent que vous faites tourner vous-même. Vous êtes responsable de cet agent, de son comportement et du sort des données qu'il reçoit.",
          "Les conversations avec un bot ne sont pas chiffrées de bout en bout : un bot ne détient aucune clé et ne pourrait rien lire autrement. L'application le signale par un bandeau explicite dans ces conversations. N'y transmettez pas d'informations sensibles.",
        ]),
        SectionLegale('Disponibilité', [
          "Le service est fourni en l'état, sans garantie de disponibilité continue. Des interruptions peuvent survenir pour maintenance, mise à jour ou incident.",
          "L'éditeur s'efforce d'assurer la continuité du service sans y être tenu par une obligation de résultat.",
        ]),
        SectionLegale('Suppression du compte', [
          "Vous pouvez supprimer votre compte à tout moment depuis l'application. La suppression entraîne l'effacement de votre profil et de vos identifiants.",
          "Les messages déjà reçus par vos correspondants restent sur leurs appareils : le service ne peut pas les y effacer, pas plus qu'une lettre ne se reprend une fois distribuée.",
        ]),
        SectionLegale('Responsabilité', [
          "L'éditeur ne peut être tenu responsable des contenus échangés par les utilisateurs, dont il n'a pas connaissance, ni des dommages résultant d'un usage du service contraire aux présentes conditions.",
        ]),
        SectionLegale('Modification des conditions', [
          "Les présentes conditions peuvent être modifiées. La date de mise à jour figure en tête du document, et les changements notables vous seront signalés dans l'application.",
        ]),
        SectionLegale('Droit applicable', [
          'Les présentes conditions sont soumises au droit français.',
          'En cas de différend, une solution amiable sera recherchée avant toute action contentieuse.',
        ]),
      ],
    );
  }
}
