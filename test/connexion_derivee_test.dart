import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/core/utils/derivation_mot_de_passe.dart';
import 'package:rempart_app/services/connexion_derivee.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _secrets = SecretsDuMotDePasse(connexion: 'R2p-derive', coffre: 'coffre');
const _motDePasse = 'le-vrai-mot-de-passe';

const _refus = AuthException(
  'Invalid login credentials',
  statusCode: '400',
  code: 'invalid_credentials',
);

/// Un serveur factice, qui dit ce qu'il a reçu.
class _Serveur {
  _Serveur(this.accepte);

  /// Ce que le serveur accepte comme mot de passe, ou null pour tout refuser.
  final String? accepte;

  /// Erreur rendue pour tout ce qui n'est pas accepté.
  AuthException erreur = _refus;

  final recu = <String>[];

  Future<String> seConnecter(String secret) async {
    recu.add(secret);
    if (secret == accepte) return 'session';
    throw erreur;
  }
}

void main() {
  late bool migre;

  ConnexionDerivee<String> connexion(_Serveur serveur, {bool repli = true}) =>
      ConnexionDerivee(
        seConnecter: serveur.seConnecter,
        dejaMigre: () async => migre,
        memoriserMigre: () async => migre = true,
        repliPermis: repli,
      );

  setUp(() => migre = false);

  test('un compte migré entre avec la valeur dérivée, et seulement elle',
      () async {
    final serveur = _Serveur(_secrets.connexion);
    final issue = await connexion(serveur).connecter(_secrets, _motDePasse);
    expect(issue.ancienMotDePasse, isFalse);
    expect(serveur.recu, [_secrets.connexion]);
    expect(migre, isTrue, reason: 'le repli doit être fermé ensuite');
  });

  test("un compte d'avant la dérivation entre par le repli, et reste à migrer",
      () async {
    final serveur = _Serveur(_motDePasse);
    final issue = await connexion(serveur).connecter(_secrets, _motDePasse);
    expect(issue.ancienMotDePasse, isTrue);
    expect(serveur.recu, [_secrets.connexion, _motDePasse]);
    expect(migre, isFalse);
  });

  test(
      "un appareil qui a vu le compte migré n'envoie JAMAIS le mot de passe, "
      'même si le serveur refuse la valeur dérivée', () async {
    // C'est l'attaque : un serveur malveillant refuse exprès la valeur
    // dérivée pour se faire envoyer le vrai mot de passe.
    migre = true;
    final serveur = _Serveur(_motDePasse);
    await expectLater(
      connexion(serveur).connecter(_secrets, _motDePasse),
      throwsA(isA<AuthException>()),
    );
    expect(serveur.recu, [_secrets.connexion]);
  });

  test("une panne ou une limite de débit n'ouvre pas le repli", () async {
    final serveur = _Serveur(_motDePasse)
      ..erreur = const AuthException(
        'Request rate limit reached',
        statusCode: '429',
        code: 'over_request_rate_limit',
      );
    await expectLater(
      connexion(serveur).connecter(_secrets, _motDePasse),
      throwsA(isA<AuthException>()),
    );
    expect(serveur.recu, [_secrets.connexion]);
  });

  test('sans repli permis, le mot de passe ne part jamais', () async {
    final serveur = _Serveur(_motDePasse);
    await expectLater(
      connexion(serveur, repli: false).connecter(_secrets, _motDePasse),
      throwsA(isA<AuthException>()),
    );
    expect(serveur.recu, [_secrets.connexion]);
  });

  test('un mot de passe faux est refusé, après les deux essais', () async {
    final serveur = _Serveur(null);
    await expectLater(
      connexion(serveur).connecter(_secrets, _motDePasse),
      throwsA(isA<AuthException>()),
    );
    expect(serveur.recu, hasLength(2));
    expect(migre, isFalse);
  });
}
