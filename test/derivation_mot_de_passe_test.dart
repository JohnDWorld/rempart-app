import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/core/utils/derivation_mot_de_passe.dart';

/// Tient la place de PBKDF2 (celui de vodozemac, que le test ne sait pas
/// charger) : vérifie qu'on lui passe exactement le mot de passe, le sel et le
/// nombre d'itérations attendus, et rend la clé maîtresse que Python a
/// calculée pour eux (`hashlib.pbkdf2_hmac('sha512', …, 500000, 32)`). Le
/// calcul complet en Dart pur prend 45 secondes.
Uint8List _pbkdf2Controle(List<int> motDePasse, List<int> sel, int iterations) {
  expect(utf8.decode(motDePasse), 'motdepasse2026');
  expect(utf8.decode(sel), 'rempart-mot-de-passe:jean.dupont@exemple.fr');
  expect(iterations, 500000);
  return Uint8List.fromList(
    _hex('ea0db592f645631af7b483e4c6e73c54d0c6e1cc53d5a06687f30bcd9d034bbc'),
  );
}

List<int> _hex(String h) => [
      for (var i = 0; i < h.length; i += 2)
        int.parse(h.substring(i, i + 2), radix: 16),
    ];

/// Substitut rapide, pour les propriétés qui ne dépendent pas de l'algorithme.
Uint8List _pbkdf2Rapide(List<int> motDePasse, List<int> sel, int iterations) =>
    Uint8List.fromList(
      crypto.sha256.convert([...motDePasse, 0, ...sel]).bytes,
    );

void main() {
  test('rend exactement le vecteur calculé par Python', () {
    // Vecteur produit par `hashlib.pbkdf2_hmac('sha512', …, 500000, 32)` et
    // `hmac`, une implémentation indépendante : si la composition changeait
    // (sel, étiquettes, encodage), tous les comptes existants seraient
    // refusés à la connexion suivante.
    final secrets = deriverSecrets(
      email: '  Jean.Dupont@Exemple.FR ',
      motDePasse: 'motdepasse2026',
      pbkdf2: _pbkdf2Controle,
    );
    expect(
      secrets.connexion,
      'R2p-gNF7GbmKMoNqCbc9DikFVwoOt58uPiJWc1gfj4YTuqw',
    );
    expect(secrets.coffre, 'Qf5DGQoNe5AHfp6RN-LBF29hwKjEVCthIAf3nAG0jRo');
  });

  test("la valeur du serveur et celle du coffre n'ont rien en commun", () {
    final secrets = deriverSecrets(
      email: 'a@b.fr',
      motDePasse: 'motdepasse2026',
      pbkdf2: _pbkdf2Rapide,
    );
    expect(secrets.connexion, startsWith(prefixeConnexion));
    expect(
      secrets.connexion.substring(prefixeConnexion.length),
      isNot(secrets.coffre),
    );
    // Le mot de passe ne transparaît dans aucune des deux.
    expect(secrets.connexion, isNot(contains('motdepasse2026')));
    expect(secrets.coffre, isNot(contains('motdepasse2026')));
  });

  test("l'adresse est lue sans casse ni espaces, comme Supabase", () {
    SecretsDuMotDePasse pour(String email) => deriverSecrets(
          email: email,
          motDePasse: 'motdepasse2026',
          pbkdf2: _pbkdf2Rapide,
        );
    expect(
        pour(' Jean@Exemple.fr ').connexion, pour('jean@exemple.fr').connexion);
    expect(pour('jean@exemple.fr').connexion,
        isNot(pour('paul@exemple.fr').connexion));
  });

  test('la valeur du serveur tient dans la limite de bcrypt (72 octets)', () {
    final secrets = deriverSecrets(
      email: 'a@b.fr',
      motDePasse: 'x',
      pbkdf2: _pbkdf2Rapide,
    );
    expect(utf8.encode(secrets.connexion).length, lessThanOrEqualTo(72));
  });
}
