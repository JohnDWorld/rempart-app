import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/derivation_mot_de_passe.dart';

/// Repli sur le mot de passe tel quel, pour les comptes créés avant la
/// dérivation.
///
/// **À couper avant l'ouverture publique** (liste des tâches du dépôt, « Avant
/// de déposer sur les boutiques »). Tant qu'il existe,
/// un serveur malveillant peut refuser exprès la valeur dérivée pour se faire
/// envoyer le vrai mot de passe. [ConnexionDerivee] ferme cette porte sur tout
/// appareil qui a déjà vu le compte migré, mais un appareil neuf n'a aucun
/// moyen de le savoir : seule la suppression du repli la ferme partout. Un
/// compte encore ancien à ce moment-là passera par « mot de passe oublié ».
const repliAncienMotDePasse = true;

/// Clé posée dans les métadonnées Supabase d'un compte migré.
///
/// Elle ne décide de rien à la connexion (le serveur pourrait mentir) : elle
/// sert à compter, côté base, les comptes qui restent à migrer avant de
/// couper [repliAncienMotDePasse].
const cleVersionMotDePasse = 'mot_de_passe_v';

/// Issue d'une connexion par mot de passe.
class IssueConnexion<R> {
  const IssueConnexion(this.reponse, {required this.ancienMotDePasse});

  final R reponse;

  /// Le compte a accepté le mot de passe tel quel : il date d'avant la
  /// dérivation et reste à migrer. Son coffre s'ouvre encore avec le mot de
  /// passe tel quel.
  final bool ancienMotDePasse;
}

/// Décide ce qui part au serveur à la connexion.
///
/// La valeur dérivée d'abord. Le mot de passe tel quel seulement si elle est
/// refusée comme identifiants invalides, que le repli est permis, et que cet
/// appareil n'a jamais vu ce compte migré. Ce dernier point est la défense
/// contre le déclassement : sans lui, un serveur malveillant n'aurait qu'à
/// refuser la valeur dérivée pour recevoir le vrai mot de passe.
class ConnexionDerivee<R> {
  ConnexionDerivee({
    required this.seConnecter,
    required this.dejaMigre,
    required this.memoriserMigre,
    this.repliPermis = repliAncienMotDePasse,
  });

  /// Ouvre la session avec ce qui est passé comme mot de passe serveur.
  final Future<R> Function(String motDePasseServeur) seConnecter;

  /// Cet appareil a-t-il déjà ouvert ce compte avec la valeur dérivée ?
  final Future<bool> Function() dejaMigre;

  /// Retient que ce compte est migré, pour ne plus jamais se replier.
  final Future<void> Function() memoriserMigre;

  final bool repliPermis;

  Future<IssueConnexion<R>> connecter(
    SecretsDuMotDePasse secrets,
    String motDePasse,
  ) async {
    try {
      final reponse = await seConnecter(secrets.connexion);
      await memoriserMigre();
      return IssueConnexion(reponse, ancienMotDePasse: false);
    } on AuthException catch (e) {
      if (!repliPermis || !identifiantsRefuses(e) || await dejaMigre()) {
        rethrow;
      }
      final reponse = await seConnecter(motDePasse);
      return IssueConnexion(reponse, ancienMotDePasse: true);
    }
  }
}

/// Le serveur a-t-il refusé le couple adresse et mot de passe ?
///
/// Seul ce refus autorise le repli : une panne réseau ou une limite de débit
/// ne dit rien de l'âge du compte, et y répondre en envoyant le mot de passe
/// tel quel le livrerait pour rien.
bool identifiantsRefuses(AuthException e) =>
    e.code == 'invalid_credentials' ||
    e.message.toLowerCase().contains('invalid login credentials');
