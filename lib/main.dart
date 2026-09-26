import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/amorcage.dart';
import 'app/app.dart';
import 'app/router.dart';
import 'core/constants/supabase_constants.dart';
import 'core/rapports_plantage.dart';
import 'data/providers/contenu_notifications.dart';
import 'data/providers/mode_theme.dart';
import 'data/providers/taille_texte.dart';
import 'data/services/notification_service.dart';
import 'data/services/presence_isolate.dart';
import 'data/services/push_service.dart';

/// Argument passé par UnifiedPush quand il relance l'app, fermée, pour lui
/// remettre une notification poussée.
const _argArrierePlan = '--unifiedpush-bg';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Le .env doit être lu avant tout le reste : c'est lui qui porte l'adresse
  // du collecteur de plantages, et l'amorçage se déroule ensuite à l'intérieur
  // de la zone surveillée.
  await dotenv.load();

  await lancerAvecRapportsDePlantage(() => _demarrer(args));
}

Future<void> _demarrer(List<String> args) async {
  // Initialiser les données de locale pour le formatage des dates en français
  // (DateFormat.E('fr'), MMMd('fr')... dans les tuiles de conversation), sinon
  // LocaleDataException dès qu'une date localisée est formatée.
  await initializeDateFormatting('fr_FR');
  Intl.defaultLocale = 'fr_FR';

  // Réveil pour une notification poussée : l'app n'a pas d'interface et le
  // travail doit rester minimal. On n'initialise donc ni Supabase ni Matrix
  // (coûteux, et la base locale peut être tenue par un autre isolate) : la
  // charge utile suffit à afficher l'avis, le contenu sera montré à
  // l'ouverture de l'app.
  // Annonce que l'application vit dans ce processus : l'isolate d'arrière-plan
  // s'en sert pour ne pas ouvrir un second client Matrix sur une base déjà
  // tenue. À poser avant tout service, et jamais dans la branche d'arrière-plan
  // ci-dessous, qui n'est justement pas l'application.
  PresenceIsolate.annoncer();

  if (args.contains(_argArrierePlan)) {
    await NotificationService.instance.init(demanderAutorisation: false);
    await PushService.instance.init();
    return;
  }

  // Initialiser Supabase avec les valeurs du .env. Le schema PostgREST est
  // configurable (defaut `public`) : sur johnserver le projet vit dans le
  // schema `rempart`, sinon les .from('profiles')/.from('matrix_credentials')
  // tapent sur `public` (vide) -> PGRST205 « table introuvable ».
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    publishableKey: dotenv.env['SUPABASE_ANON_KEY'],
    postgrestOptions: PostgrestClientOptions(schema: SupabaseConstants.schema),
  );

  _ecouterReinitialisation();

  // Les services lourds (base Matrix, chiffrement, push) sont amorcés DERRIÈRE
  // l'écran de démarrage. Les attendre ici laissait l'écran noir plus d'une
  // seconde : Flutter ne dessine rien tant que `runApp` n'est pas appelé.
  // L'amorçage part maintenant, et travaille pendant que l'interface se monte.
  unawaited(Amorcage.futur);

  // Thème choisi lu AVANT le premier rendu : injecté après coup, il ferait
  // sauter l'app du clair au sombre sous les yeux de l'utilisateur.
  final modeTheme = await chargerModeTheme();

  // Même raison pour le contenu des notifications : lu avant que la première
  // notification puisse partir, sinon elle afficherait le texte d'un
  // utilisateur qui n'en veut pas.
  final contenuNotifications = await chargerContenuNotifications();
  final tailleTexte = await chargerTailleTexte();
  NotificationService.instance.afficherContenu = contenuNotifications;

  runApp(
    ProviderScope(
      overrides: [
        modeThemeProvider.overrideWith((ref) => modeTheme),
        contenuNotificationsProvider
            .overrideWith((ref) => contenuNotifications),
        tailleTexteProvider.overrideWith((ref) => tailleTexte),
      ],
      child: const RempartApp(),
    ),
  );
}

/// Ouvre l'écran de nouveau mot de passe quand le lien du courriel arrive.
///
/// Supabase se charge seul de lire l'adresse `fr.rempart-messenger.app://`
/// (ou le fragment de l'URL sur le web) et d'en tirer une session ; il ne
/// reste qu'à écouter l'événement. Sans cela, le lien ouvrait l'application
/// sur l'accueil, connecté, sans jamais demander le nouveau mot de passe :
/// exactement ce que la personne était venue faire.
///
/// L'écoute est montée ici, hors de l'arbre des écrans, parce que l'événement
/// peut survenir avant que le premier écran existe. Le routeur porte alors le
/// relais (`reinitialisationEnAttente`).
///
/// Un lien refusé arrive par le même flux, mais en ERREUR : un lien de
/// réinitialisation ne vaut qu'un temps et ne sert qu'une fois. Sans
/// `onError`, l'application s'ouvrait sans un mot, et l'exception, que
/// personne ne rattrapait, partait comme un plantage dans les rapports.
void _ecouterReinitialisation() {
  Supabase.instance.client.auth.onAuthStateChange.listen(
    (etat) {
      if (etat.event != AuthChangeEvent.passwordRecovery) return;
      reinitialisationEnAttente = true;
      final contexte = cleNavigateurRacine.currentContext;
      // Le contexte vient d'être relu à la clé du Navigator, il ne peut pas
      // être périmé : c'est celui qui existe à cet instant, ou rien.
      // ignore: use_build_context_synchronously
      if (contexte != null) contexte.go('/reinitialiser');
    },
    onError: (Object erreur) {
      debugPrint('Lien de courriel refusé par Supabase : $erreur');
      if (erreur is! AuthException) return;
      // Connecté, on n'a que faire d'un lien de récupération : on ne déplace
      // personne hors de l'écran où il se trouve.
      if (Supabase.instance.client.auth.currentSession != null) return;
      lienPerimeEnAttente = true;
      final contexte = cleNavigateurRacine.currentContext;
      // ignore: use_build_context_synchronously
      if (contexte != null) contexte.go('/mot-de-passe-oublie');
    },
  );
}
