import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

/// Ce que l'appareil tire du mot de passe. Le mot de passe, lui, ne sort plus.
///
/// Avant, il servait tel quel à deux usages : Supabase le recevait pour ouvrir
/// la session, ET il était la phrase secrète du coffre de clés (SSSS). Le
/// serveur recevait donc à chaque connexion de quoi ouvrir le coffre, puis,
/// par la sauvegarde des clés, lire tout l'historique.
///
/// Désormais, une dérivation lente (PBKDF2) produit une clé maîtresse, d'où
/// sortent deux valeurs indépendantes (HKDF, deux étiquettes). [connexion]
/// part au serveur à la place du mot de passe ; [coffre] ne quitte pas
/// l'appareil. Connaître l'une ne dit rien de l'autre : pour rejoindre le
/// coffre, le serveur doit DEVINER le mot de passe, et chaque essai lui coûte
/// une dérivation entière.
class SecretsDuMotDePasse {
  const SecretsDuMotDePasse({required this.connexion, required this.coffre});

  /// Envoyé à Supabase à la place du mot de passe.
  final String connexion;

  /// Phrase secrète du coffre SSSS. Ne quitte jamais l'appareil.
  final String coffre;
}

/// PBKDF2-HMAC-SHA-512, rendant 32 octets.
///
/// Injecté plutôt qu'importé : l'application passe celui de vodozemac (natif,
/// rapide), qu'un test ne sait pas charger.
typedef Pbkdf2 = Uint8List Function(
  List<int> motDePasse,
  List<int> sel,
  int iterations,
);

/// Le coût que l'app paie déjà pour ouvrir le coffre Matrix à chaque
/// connexion : une demi-seconde environ sur un téléphone.
const iterationsDerivation = 500000;

/// Préfixe de la valeur envoyée au serveur.
///
/// Il garantit majuscule, chiffre, minuscule et symbole, quelles que soient
/// les règles de mot de passe réglées dans Supabase : une valeur tirée au
/// hasard pourrait manquer d'un chiffre et se faire refuser. Il nomme aussi la
/// version du schéma, pour une éventuelle migration future.
const prefixeConnexion = 'R2p-';

/// Dérive les deux secrets du mot de passe.
///
/// Le sel est l'adresse du compte : il doit être connu AVANT la connexion,
/// donc sans rien demander au serveur, et il empêche qu'un même mot de passe
/// donne la même valeur pour deux comptes.
SecretsDuMotDePasse deriverSecrets({
  required String email,
  required String motDePasse,
  required Pbkdf2 pbkdf2,
}) {
  final sel = utf8.encode('rempart-mot-de-passe:${normaliserEmail(email)}');
  final maitre = pbkdf2(utf8.encode(motDePasse), sel, iterationsDerivation);
  return SecretsDuMotDePasse(
    connexion: '$prefixeConnexion${_base64(_hkdf(maitre, 'rempart-connexion'))}',
    coffre: _base64(_hkdf(maitre, 'rempart-coffre')),
  );
}

/// L'adresse telle qu'elle entre dans le sel.
///
/// Supabase ne distingue pas les majuscules d'une adresse : sans cette
/// normalisation, « Jean@… » et « jean@… » ouvriraient le même compte avec
/// deux valeurs différentes, dont une refusée.
String normaliserEmail(String email) => email.trim().toLowerCase();

/// HKDF-SHA-256 (RFC 5869) pour une sortie de 32 octets, soit un seul bloc.
Uint8List _hkdf(List<int> cle, String etiquette) {
  final prk = crypto.Hmac(crypto.sha256, Uint8List(32)).convert(cle).bytes;
  return Uint8List.fromList(
    crypto.Hmac(crypto.sha256, prk)
        .convert([...utf8.encode(etiquette), 1]).bytes,
  );
}

String _base64(List<int> octets) =>
    base64Url.encode(octets).replaceAll('=', '');
