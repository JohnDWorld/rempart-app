import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/core/utils/erreur_de_lien.dart';
import 'package:rempart_app/presentation/screens/auth/mot_de_passe_oublie_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Un lien de réinitialisation refusé (périmé, ou déjà servi) ramène à la
/// demande d'un nouveau lien. Sans l'encart, la personne retombait devant le
/// formulaire qu'elle venait de remplir, sans rien comprendre à ce qui s'était
/// passé.
void main() {
  Future<void> ouvrir(WidgetTester tester, {required bool lienPerime}) =>
      tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: MotDePasseOublieScreen(lienPerime: lienPerime),
          ),
        ),
      );

  testWidgets('dit pourquoi le lien a été refusé', (tester) async {
    await ouvrir(tester, lienPerime: true);
    expect(find.textContaining("n'est plus valable"), findsOneWidget);
  });

  testWidgets('offre un retour quand rien ne le précède', (tester) async {
    // Seul dans la pile, comme quand on arrive par le lien du courriel.
    await ouvrir(tester, lienPerime: true);
    expect(find.text('Revenir à la connexion'), findsOneWidget);
  });

  testWidgets("se tait quand on vient d'ailleurs", (tester) async {
    await ouvrir(tester, lienPerime: false);
    expect(find.textContaining("n'est plus valable"), findsNothing);
  });

  group('ce qui compte comme un lien refusé', () {
    /// L'erreur exactement telle que Supabase la fabrique en lisant l'adresse
    /// de retour d'un lien périmé : pas une imitation.
    Future<Object> erreurDeLAdresse(String adresse) async {
      try {
        await GoTrueClient(autoRefreshToken: false)
            .getSessionFromUrl(Uri.parse(adresse));
      } catch (e) {
        return e;
      }
      fail("l'adresse aurait dû être refusée");
    }

    test("un lien périmé, dans les deux formes d'adresse de retour", () async {
      for (final separateur in ['?', '#']) {
        final erreur = await erreurDeLAdresse(
          'fr.rempart-messenger.app://reset-callback${separateur}error=access_denied'
          '&error_code=otp_expired'
          '&error_description=Email+link+is+invalid+or+has+expired',
        );
        expect(erreurDeLien(erreur), isTrue, reason: separateur);
      }
    });

    test("un code refusé, ou ouvert sur l'appareil qui ne l'a pas demandé", () {
      expect(
        erreurDeLien(
          const AuthApiException(
            'invalid flow state, no valid flow state found',
            statusCode: '404',
            code: 'flow_state_not_found',
          ),
        ),
        isTrue,
      );
      expect(
        erreurDeLien(
          const AuthPKCEGrantCodeExchangeError(
            'Code verifier could not be found in local storage.',
          ),
        ),
        isTrue,
      );
    });

    test("les pannes de la session n'en sont pas", () {
      // Vues dans le journal d'une session ordinaire : aucun lien ouvert.
      expect(
        erreurDeLien(
          AuthRetryableFetchException(
            message: 'Connection closed before full header was received',
          ),
        ),
        isFalse,
      );
      expect(
        erreurDeLien(
          const AuthApiException(
            'Invalid Refresh Token: Refresh Token Not Found',
            statusCode: '400',
            code: 'refresh_token_not_found',
          ),
        ),
        isFalse,
      );
      expect(
        erreurDeLien(
          const AuthException('Session expired.', code: 'session_expired'),
        ),
        isFalse,
      );
      expect(erreurDeLien(AuthSessionMissingException()), isFalse);
      expect(erreurDeLien(StateError('autre chose')), isFalse);
    });
  });
}
