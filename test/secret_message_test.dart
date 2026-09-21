import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/core/utils/secret_message.dart';

void main() {
  group('ressembleAUnSecret', () {
    test('reconnaît un code envoyé seul', () {
      expect(ressembleAUnSecret('483920'), isTrue);
      expect(ressembleAUnSecret('  74920.'), isTrue);
      expect(ressembleAUnSecret('483 920'), isTrue);
    });

    test('reconnaît un code annoncé', () {
      expect(ressembleAUnSecret('Ton code de vérification est 4839'), isTrue);
      expect(ressembleAUnSecret('OTP: 928374'), isTrue);
      // Vu en clair dans l'aperçu de la liste le 2026-08-25, alors que la
      // bulle le masquait bien.
      expect(ressembleAUnSecret("Le code d'entrée est 0672"), isTrue);
      expect(ressembleAUnSecret('le mdp du wifi : Maison2026x'), isTrue);
      expect(
        ressembleAUnSecret('Mot de passe du compte : Tr0ub4dour'),
        isTrue,
      );
    });

    test('laisse passer une conversation ordinaire', () {
      expect(ressembleAUnSecret('On se voit à 18h30 ?'), isFalse);
      expect(ressembleAUnSecret('2026'), isFalse, reason: 'une année');
      expect(ressembleAUnSecret('Ça fait 1500 euros'), isFalse);
      expect(ressembleAUnSecret('Oui'), isFalse);
      expect(ressembleAUnSecret(''), isFalse);
    });

    test('un mot-clé seul ne suffit pas, il faut aussi la forme du secret', () {
      expect(ressembleAUnSecret("J'ai oublié mon mot de passe"), isFalse);
      expect(ressembleAUnSecret('Tu as le code ?'), isFalse);
    });

    test('ignore un texte long, où le mot-clé ne prouve plus rien', () {
      final long = 'code ${'blabla ' * 60} 123456';
      expect(long.length, greaterThan(300));
      expect(ressembleAUnSecret(long), isFalse);
    });

    test("« code » dans un autre mot n'annonce rien", () {
      // `contains` trouvait « code » dans « codex », et un message d'agent
      // annonçant son modèle disparaissait derrière le masque. Le mot doit
      // être un mot, pas un morceau.
      expect(
        ressembleAUnSecret(
          'Nouvelle session démarrée !\n'
          'Model: gpt-5.6-sol\n'
          'Provider: openai-codex\n'
          'Context: 65K tokens',
        ),
        isFalse,
      );
    });

    test('les mots collés à un autre ne comptent pas non plus', () {
      for (final texte in [
        'le décodeur ffmpeg rend 4096 images',
        'la codebase fait 12000 lignes',
        'pinned le message abc123 du salon',
      ]) {
        expect(ressembleAUnSecret(texte), isFalse, reason: texte);
      }
    });

    test('mais le vrai mot annonce toujours un secret', () {
      // La correction ne doit pas ouvrir de brèche : mot entier, forme de
      // secret, le masque tient.
      expect(ressembleAUnSecret('ton code est 428193'), isTrue);
      expect(ressembleAUnSecret('mot de passe : Tr0ub4dour'), isTrue);
      expect(ressembleAUnSecret('code: ab12cd34'), isTrue);
    });
  });
}
