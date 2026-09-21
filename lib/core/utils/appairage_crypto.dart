import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart' as pc;

/// Cryptographie de l'appairage par QR, jumelle de `appairage.py`.
///
/// Tout est en Dart pur (`crypto` et `pointycastle`, déjà tirés par le SDK
/// Matrix), et non par WebCrypto ni par la bibliothèque native : `crypto.subtle`
/// n'existe pas hors contexte sécurisé, or Rempart est servi en HTTP sur le
/// tailnet ; et une bibliothèque native ne se charge pas dans un test.
///
/// Les deux implémentations dérivent leurs clés chacune de leur côté : un test
/// rejoue de part et d'autre le même vecteur, sans quoi une divergence ne se
/// verrait qu'au premier appairage réel, sous la forme d'un « paquet altéré »
/// incompréhensible.
class ClesAppairage {
  const ClesAppairage(this.chiffrement, this.authentification);

  final Uint8List chiffrement;
  final Uint8List authentification;
}

const _info = 'rempart-appairage';

/// HKDF-SHA256 (RFC 5869), réduit à ce dont on a besoin.
///
/// Deux clés et non une : celle qui chiffre ne doit pas être celle qui
/// authentifie.
ClesAppairage deriverCles(Uint8List secret) {
  final prk = _hmac(Uint8List(32), secret);
  final info = utf8.encode(_info);
  final k1 = _hmac(prk, Uint8List.fromList([...info, 1]));
  final k2 = _hmac(prk, Uint8List.fromList([...k1, ...info, 2]));
  return ClesAppairage(k1, k2);
}

Uint8List _hmac(Uint8List cle, Uint8List message) => Uint8List.fromList(
      crypto.Hmac(crypto.sha256, cle).convert(message).bytes,
    );

/// AES-256 en mode compteur, identique des deux côtés.
///
/// Le mode est symétrique : la même fonction chiffre et déchiffre.
Uint8List _aesCtr(Uint8List cle, Uint8List iv, Uint8List donnees) {
  final moteur = pc.CTRStreamCipher(pc.AESEngine())
    ..init(true, pc.ParametersWithIV(pc.KeyParameter(cle), iv));
  return moteur.process(donnees);
}

/// Vérifie le sceau puis déchiffre le paquet déposé par la passerelle.
///
/// L'ordre compte : on ne déchiffre **rien** avant d'avoir constaté que le
/// paquet n'a pas bougé. AES-CTR ne protège que la confidentialité, un tiers
/// pourrait sinon retourner des bits sans que personne s'en aperçoive.
Uint8List ouvrirPaquet(Uint8List secret, Map<String, dynamic> paquet) {
  final cles = deriverCles(secret);
  final iv = base64.decode(paquet['iv'] as String);
  final chiffre = base64.decode(paquet['chiffre'] as String);
  final macRecu = base64.decode(paquet['mac'] as String);

  final macAttendu = _hmac(
    cles.authentification,
    Uint8List.fromList([...iv, ...chiffre]),
  );
  if (!_memeSecret(macAttendu, macRecu)) {
    throw const FormatException('paquet altéré');
  }
  return _aesCtr(
    cles.chiffrement,
    Uint8List.fromList(iv),
    Uint8List.fromList(chiffre),
  );
}

/// Comparaison à temps constant.
///
/// Sortir à la première différence laisserait mesurer, essai après essai, le
/// nombre d'octets déjà justes.
bool _memeSecret(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a[i] ^ b[i];
  }
  return difference == 0;
}

/// Secret de 32 octets, tiré pour un appairage.
Uint8List tirerSecret() {
  final rng = Random.secure();
  return Uint8List.fromList(
    List<int>.generate(32, (_) => rng.nextInt(256)),
  );
}

/// Empreinte transmise à la passerelle. Le secret, lui, ne quitte le QR que
/// pour l'appareil qui le scanne.
String empreinteDe(Uint8List secret) {
  return crypto.sha256.convert(secret).toString();
}

/// Encodage du secret dans le QR et dans les requêtes.
String secretEnTexte(Uint8List secret) =>
    base64Url.encode(secret).replaceAll('=', '');

Uint8List secretDepuisTexte(String texte) {
  final complete = texte.padRight(texte.length + (4 - texte.length % 4) % 4, '=');
  final octets = base64Url.decode(complete);
  if (octets.length != 32) {
    throw const FormatException('secret de 32 octets attendu');
  }
  return Uint8List.fromList(octets);
}

/// Chiffre un message avec les clés et l'IV donnés.
///
/// Le client n'a jamais à chiffrer en vrai : c'est la passerelle qui dépose le
/// paquet. Exposé pour que le test puisse rejouer le vecteur commun, et donc
/// constater que les deux côtés retiennent la même convention de compteur.
Uint8List scellerPourTest(ClesAppairage cles, Uint8List iv, List<int> clair) =>
    _aesCtr(cles.chiffrement, iv, Uint8List.fromList(clair));
