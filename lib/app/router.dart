import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../presentation/screens/accueil_screen.dart';
import '../presentation/screens/auth/connexion_qr_screen.dart';
import '../presentation/screens/auth/login_screen.dart';
import '../presentation/screens/auth/mot_de_passe_oublie_screen.dart';
import '../presentation/screens/auth/register_screen.dart';
import '../presentation/screens/auth/reinitialiser_mot_de_passe_screen.dart';
import '../presentation/screens/bots/bot_directory_screen.dart';
import '../presentation/screens/bots/bots_hub_screen.dart';
import '../presentation/screens/bots/bots_screen.dart';
import '../presentation/screens/bots/boutique_agents_screen.dart';
import '../presentation/screens/bots/my_bots_screen.dart';
import '../presentation/screens/chat/chat_screen.dart';
import '../presentation/screens/chat/new_chat_screen.dart';
import '../presentation/screens/chat/new_group_screen.dart';
import '../presentation/screens/conversations/archived_conversations_screen.dart';
import '../presentation/screens/legal/conditions_utilisation_screen.dart';
import '../presentation/screens/legal/licences_screen.dart';
import '../presentation/screens/legal/politique_confidentialite_screen.dart';
import '../presentation/screens/profile/add_members_screen.dart';
import '../presentation/screens/profile/group_info_screen.dart';
import '../presentation/screens/profile/modifier_profil_screen.dart';
import '../presentation/screens/profile/user_info_screen.dart';
import '../presentation/screens/settings/appareils_screen.dart';
import '../presentation/screens/settings/changer_mot_de_passe_screen.dart';
import '../presentation/screens/settings/settings_screen.dart';
import '../presentation/screens/settings/utilisateurs_bloques_screen.dart';
import '../presentation/screens/splash/splash_screen.dart';

/// Le Navigator de l'application, atteignable de partout.
///
/// Sert à ouvrir une fenêtre depuis du code qui ne vit pas dans l'arbre des
/// écrans : l'écoute des demandes de vérification, par exemple, est montée
/// dans le `builder` de l'application, donc **au-dessus** du Navigator que
/// GoRouter crée. `showDialog` y cherchait un Navigator inexistant.
final cleNavigateurRacine = GlobalKey<NavigatorState>();

/// Vrai quand Supabase vient d'ouvrir une session de récupération (le lien
/// « mot de passe oublié » du courriel) et que l'écran correspondant n'a pas
/// encore été atteint. Posé par l'écoute montée dans `main`.
bool reinitialisationEnAttente = false;

/// Provider pour le router
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: cleNavigateurRacine,
    initialLocation: '/',
    debugLogDiagnostics: true,

    // Redirection basée sur l'état d'authentification
    redirect: (context, state) {
      final session = Supabase.instance.client.auth.currentSession;
      final isLoggedIn = session != null;
      // `/connexion-qr` compte parmi les pages d'authentification : s'y
      // connecter est justement ce qu'on y vient faire, et la garde y
      // renverrait sinon vers `/login` en boucle.
      final isAuthRoute = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register' ||
          state.matchedLocation == '/connexion-qr' ||
          state.matchedLocation == '/mot-de-passe-oublie';

      // La réinitialisation arrive avec une session ouverte, celle que le lien
      // du courriel vient de créer : la garde « connecté donc accueil » l'en
      // chasserait avant même qu'elle s'affiche. C'est la seule page qui se
      // visite justement parce qu'on est connecté sans connaître son mot de
      // passe.
      if (state.matchedLocation == '/reinitialiser') {
        reinitialisationEnAttente = false;
        return null;
      }
      // Le lien du courriel peut réveiller l'application avant que le routeur
      // existe : l'écouteur n'a alors aucun contexte où naviguer. Il pose ce
      // drapeau, et la première navigation venue (celle de l'écran de
      // démarrage) atterrit ici.
      if (reinitialisationEnAttente) return '/reinitialiser';
      final isSplash = state.matchedLocation == '/';

      // Splash screen - pas de redirection
      if (isSplash) return null;

      // Non connecté et pas sur une page auth -> rediriger vers login
      if (!isLoggedIn && !isAuthRoute) {
        return '/login';
      }

      // Connecté et sur une page auth -> rediriger vers home
      if (isLoggedIn && isAuthRoute) {
        return '/home';
      }

      return null;
    },

    routes: [
      // Splash
      GoRoute(
        path: '/',
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),

      // Auth
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/mot-de-passe-oublie',
        name: 'mot-de-passe-oublie',
        builder: (context, state) => const MotDePasseOublieScreen(),
      ),
      GoRoute(
        path: '/reinitialiser',
        name: 'reinitialiser',
        builder: (context, state) => const ReinitialiserMotDePasseScreen(),
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/connexion-qr',
        name: 'connexion-qr',
        builder: (context, state) => const ConnexionQrScreen(),
      ),

      // Home (redirige vers conversations)
      GoRoute(
        path: '/home',
        name: 'home',
        builder: (context, state) => const AccueilScreen(),
      ),

      // Conversations
      GoRoute(
        path: '/conversations',
        name: 'conversations',
        builder: (context, state) => const AccueilScreen(),
      ),

      // Chat
      GoRoute(
        path: '/chat/:conversationId',
        name: 'chat',
        builder: (context, state) {
          final conversationId = state.pathParameters['conversationId']!;
          return ChatScreen(conversationId: conversationId);
        },
      ),

      // Nouveau chat
      GoRoute(
        path: '/new-chat',
        name: 'new-chat',
        builder: (context, state) => const NewChatScreen(),
      ),

      // Nouveau groupe
      GoRoute(
        path: '/new-group',
        name: 'new-group',
        builder: (context, state) => const NewGroupScreen(),
      ),

      // Fiche publique d'une personne (nom touché dans l'en-tête d'un
      // tête-à-tête, ou membre d'un groupe). Le mxid contient « @ » et « : » :
      // il voyage encodé dans le chemin.
      GoRoute(
        path: '/user/:mxid',
        name: 'user',
        builder: (context, state) => UserInfoScreen(
          mxid: Uri.decodeComponent(state.pathParameters['mxid']!),
        ),
      ),

      // Fiche d'un groupe (nom touché dans l'en-tête d'une conversation de
      // groupe).
      GoRoute(
        path: '/group/:roomId',
        name: 'group',
        builder: (context, state) => GroupInfoScreen(
          roomId: Uri.decodeComponent(state.pathParameters['roomId']!),
        ),
      ),

      // Ajout de membres à un groupe existant.
      GoRoute(
        path: '/group/:roomId/add',
        name: 'group-add',
        builder: (context, state) => AddMembersScreen(
          roomId: Uri.decodeComponent(state.pathParameters['roomId']!),
        ),
      ),

      // Choix : ses propres bots ou ceux fournis avec l'app
      GoRoute(
        path: '/bots',
        name: 'bots',
        builder: (context, state) => const BotsHubScreen(),
      ),

      // Catalogue des bots systeme
      GoRoute(
        path: '/bots/system',
        name: 'system-bots',
        builder: (context, state) => const BotsScreen(),
      ),

      // Mes bots (création/gestion, à la BotFather)
      GoRoute(
        path: '/my-bots',
        name: 'my-bots',
        builder: (context, state) => const MyBotsScreen(),
      ),

      // Boutique à agents : commander un agent sur mesure
      GoRoute(
        path: '/boutique-agents',
        name: 'boutique-agents',
        builder: (context, state) => const BoutiqueAgentsScreen(),
      ),

      // Annuaire des bots publics (découverte)
      GoRoute(
        path: '/bot-directory',
        name: 'bot-directory',
        builder: (context, state) => const BotDirectoryScreen(),
      ),

      GoRoute(
        path: '/profil/modifier',
        name: 'modifier-profil',
        builder: (context, state) => const ModifierProfilScreen(),
      ),

      // Settings
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/settings/appareils',
        name: 'appareils',
        builder: (context, state) => const AppareilsScreen(),
      ),
      GoRoute(
        path: '/settings/mot-de-passe',
        name: 'mot-de-passe',
        builder: (context, state) => const ChangerMotDePasseScreen(),
      ),
      GoRoute(
        path: '/settings/bloques',
        name: 'bloques',
        builder: (context, state) => const UtilisateursBloquesScreen(),
      ),
      GoRoute(
        path: '/legal/conditions',
        name: 'conditions',
        builder: (context, state) => const ConditionsUtilisationScreen(),
      ),
      GoRoute(
        path: '/legal/confidentialite',
        name: 'confidentialite',
        builder: (context, state) => const PolitiqueConfidentialiteScreen(),
      ),
      GoRoute(
        path: '/legal/licences',
        name: 'licences',
        builder: (context, state) => const LicencesScreen(),
      ),

      // Archives
      GoRoute(
        path: '/archives',
        name: 'archives',
        builder: (context, state) => const ArchivedConversationsScreen(),
      ),
    ],

    // Page d'erreur
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Page non trouvée',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(state.uri.toString()),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/'),
              child: const Text("Retour à l'accueil"),
            ),
          ],
        ),
      ),
    ),
  );
});
