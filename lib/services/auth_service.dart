import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/plateforme.dart';
import '../data/services/bot_gateway_service.dart';
import '../data/services/matrix_service.dart';
import '../data/services/push_service.dart';
import '../data/services/sync_arriere_plan_service.dart';

/// Provider pour le service d'authentification
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(Supabase.instance.client);
});

/// Provider pour l'état de l'utilisateur courant
final currentUserProvider = StreamProvider<User?>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange.map(
    (event) => event.session?.user,
  );
});

/// Service d'authentification via Supabase + Matrix
class AuthService {
  AuthService(this._client);

  final SupabaseClient _client;

  /// Recovery key E2E générée au dernier setup (à afficher une seule fois).
  String? _pendingRecoveryKey;

  /// Future du durcissement E2E lancé en tâche de fond (voir
  /// [_startEncryptionSetup]). Permet à l'UI d'attendre la clé de récupération
  /// sans bloquer la navigation post-inscription.
  Future<String?>? _e2eSetupFuture;

  /// Client Supabase
  SupabaseClient get client => _client;

  /// Récupère puis efface la recovery key E2E en attente d'affichage.
  String? consumePendingRecoveryKey() {
    final key = _pendingRecoveryKey;
    _pendingRecoveryKey = null;
    return key;
  }

  /// Attend la fin du durcissement E2E lancé en tâche de fond (no-op s'il n'y en
  /// a pas). Ne consomme pas la clé : l'appelant lit [consumePendingRecoveryKey]
  /// seulement s'il est encore monté et prêt à l'afficher (sinon la clé reste
  /// disponible pour le prochain affichage de l'écran, jamais perdue).
  Future<void> awaitE2eSetup() async {
    final future = _e2eSetupFuture;
    if (future == null) return;
    try {
      await future;
    } catch (_) {
      // Erreurs déjà loguées dans _startEncryptionSetup.
    }
  }

  /// Lance le durcissement E2E (SSSS + cross-signing + key backup) en tâche de
  /// fond, hors du chemin critique de l'inscription/connexion (évite le gel de
  /// l'UI). La clé de récupération éventuelle est stockée dans
  /// [_pendingRecoveryKey] et exposée via [awaitPendingRecoveryKey].
  void _startEncryptionSetup(String supabasePassword, String userId) {
    _e2eSetupFuture = () async {
      try {
        final matrixPassword = await _getOrCreateMatrixPassword(userId);
        // Posée ici, avec le reste de ce qui se règle une fois connecté : la
        // règle vit côté compte, il faut donc la reposer sur chaque serveur où
        // l'on ouvre une session, pas seulement à la première.
        await MatrixService.instance.activerNotificationsDeReaction();
        final key = await MatrixService.instance
            .setupOrUnlockEncryption(supabasePassword, matrixPassword);
        _pendingRecoveryKey = key;
        return key;
      } catch (e) {
        debugPrint('Matrix: durcissement E2E (tâche de fond) échoué: $e');
        return null;
      }
    }();
  }

  /// Utilisateur courant
  User? get currentUser => _client.auth.currentUser;

  /// Session courante
  Session? get currentSession => _client.auth.currentSession;

  /// L'utilisateur est-il connecté ?
  bool get isLoggedIn => currentSession != null;

  /// Stream des changements d'état d'auth
  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  /// Inscription avec email et mot de passe (Supabase + Matrix)
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    // 1. Inscription Supabase
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      data: displayName != null ? {'display_name': displayName} : null,
    );

    if (response.user != null) {
      // 2. Créer le profil Supabase
      if (displayName != null) {
        await _createUserProfile(response.user!.id, email, displayName);
      }

      // 3. Session Matrix (awaitée, rapide) puis durcissement E2E en tâche de
      // fond : le bootstrap E2E gèle l'UI ~21s s'il est awaité ici. On laisse
      // l'app naviguer vers l'accueil tout de suite ; la clé de récupération
      // est présentée quand le setup est prêt (awaitPendingRecoveryKey).
      try {
        await ensureMatrixSession(response.user!);
        _startEncryptionSetup(password, response.user!.id);
      } catch (e) {
        debugPrint(
            "Matrix: session non établie à l'inscription (on continue): $e");
      }
    }

    return response;
  }

  /// Connexion avec email et mot de passe (Supabase + Matrix)
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    // 1. Connexion Supabase
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );

    // 2. Session Matrix (awaitée) puis durcissement/déverrouillage E2E en tâche
    // de fond (idem inscription : ne doit pas bloquer l'arrivée sur l'accueil).
    if (response.user != null) {
      try {
        await ensureMatrixSession(response.user!);
        _startEncryptionSetup(password, response.user!.id);
      } catch (e) {
        debugPrint(
            'Matrix: session non établie à la connexion (on continue): $e');
      }
    }

    return response;
  }

  /// Assure une session Matrix pour l'utilisateur Supabase (chemin unifié).
  ///
  /// Username = `u_<uuid sans tirets>`. Mot de passe aléatoire (jamais dérivé
  /// de l'UUID), stocké dans le secure storage et dans Supabase
  /// (`matrix_credentials`, RLS propriétaire). Tente la connexion, puis
  /// l'inscription si le compte n'existe pas encore.
  Future<void> ensureMatrixSession(User user) async {
    await MatrixService.instance.init();

    final username = _matrixUsername(user.id);
    final expectedMxid = MatrixService.instance.getFullUserId(username);

    // `init()` restaure la session Matrix depuis la base locale : elle peut
    // appartenir à un AUTRE utilisateur (logout Matrix échoué, app non
    // redémarrée entre deux comptes...). Ne jamais la réutiliser sans vérifier
    // son propriétaire, sinon le nouvel utilisateur voit les conversations du
    // précédent et peut écrire en son nom.
    if (MatrixService.instance.isLoggedIn) {
      final currentMxid = MatrixService.instance.currentUserId;
      if (currentMxid == expectedMxid) {
        // Bonne session, rien à rétablir. Les raccrochages (BotFather, push)
        // restent nécessaires : ils valent pour chaque démarrage, pas
        // seulement pour une connexion fraîche.
        _apresSessionMatrix();
        return;
      }

      debugPrint(
        'Matrix: session étrangère détectée ($currentMxid != $expectedMxid), '
        'fermeture avant reconnexion',
      );
      try {
        await MatrixService.instance.logout();
      } catch (e) {
        // Le SDK vide la session locale dans un `finally`, même si la requête
        // de logout échoue côté serveur : on peut poursuivre sans risque de
        // conserver la session de l'autre compte.
        debugPrint(
            'Matrix: logout serveur incomplet (session locale vidée): $e');
      }
    }

    final password = await _getOrCreateMatrixPassword(user.id);
    final displayName = user.userMetadata?['display_name'] as String?;

    try {
      await MatrixService.instance.login(
        username: username,
        password: password,
      );
      debugPrint('Matrix: connecté en tant que $username');
    } catch (loginError) {
      debugPrint('Matrix: login échoué ($loginError), tentative inscription');
      await _creerCompteMatrix(username, password, displayName);
      debugPrint('Matrix: compte créé pour $username');
    }

    _apresSessionMatrix();
  }

  /// Crée le compte Matrix, par la passerelle d'abord.
  ///
  /// La passerelle détient le secret partagé de Synapse : elle sait donc créer
  /// un compte alors que l'inscription publique est FERMÉE, et ne le fait
  /// qu'après avoir vérifié auprès de Supabase que l'adresse est confirmée.
  /// C'est ce qui permet de fermer `enable_registration` sur le serveur, une
  /// API que tout l'internet peut sinon appeler pour créer des comptes en
  /// masse, sans passer par Rempart.
  ///
  /// Le repli sur l'inscription directe reste là **pour le développement** :
  /// une instance locale n'a pas forcément de passerelle, et un serveur dont
  /// l'inscription est ouverte l'acceptera. En production il ne sert pas, la
  /// passerelle répondant la première ; s'il servait, Synapse refuserait de
  /// toute façon.
  Future<void> _creerCompteMatrix(
    String username,
    String password,
    String? displayName,
  ) async {
    try {
      await BotGatewayService().provisionMatrixAccount(password);
      await MatrixService.instance.login(
        username: username,
        password: password,
      );
      if (displayName != null && displayName.isNotEmpty) {
        await MatrixService.instance.definirNomAffiche(displayName);
      }
      return;
    } catch (e) {
      debugPrint('Matrix: provisioning par la passerelle indisponible ($e), '
          'repli sur inscription directe');
    }
    await MatrixService.instance.register(
      username: username,
      password: password,
      displayName: displayName,
    );
  }

  /// Nom affiché de l'utilisateur courant, lu dans son profil Supabase.
  ///
  /// Source de vérité des noms dans Rempart : Matrix ne fait que la recopier.
  Future<String?> _nomDuProfil() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    final row = await _client
        .from('profiles')
        .select('display_name')
        .eq('id', userId)
        .maybeSingle();
    return row?['display_name'] as String?;
  }

  /// Raccrochages effectués une fois la session Matrix disponible.
  ///
  /// Tous hors chemin critique (fire-and-forget) : ces appels réseau ne doivent
  /// jamais retarder l'arrivée sur l'accueil, ni faire échouer la connexion si
  /// un service est lent ou injoignable.
  void _apresSessionMatrix() {
    // Aligne le nom affiché côté Matrix sur le profil Supabase. Sans lui, le
    // serveur ne connaît que `u_<uuid>`, et tout ce qui lit un nom hors de
    // l'application (notification composée dans l'isolate, bots dans un
    // groupe) n'a qu'un identifiant à montrer.
    unawaited(
      _nomDuProfil().then(MatrixService.instance.harmoniserNomAffiche).catchError(
        (Object e) {
          debugPrint('Matrix: nom affiché non harmonisé (on continue): $e');
        },
      ),
    );

    // Lie le mxid Matrix au compte Supabase, pour que BotFather sache à qui
    // appartiennent les bots.
    final mxid = MatrixService.instance.currentUserId;
    if (mxid != null) {
      unawaited(
        BotGatewayService().linkMatrix(mxid).catchError((Object e) {
          debugPrint('BotFather: link mxid non effectué (on continue): $e');
        }),
      );
    }

    // Notifications : UnifiedPush si un distributeur est installé (couvre
    // l'app fermée), sinon repli sur un service de premier plan qui garde la
    // connexion de l'app vivante en arrière-plan. Les deux sont exclusifs :
    // inutile d'imposer une notification permanente quand le push suffit.
    unawaited(
      PushService.instance.demarrer().then((transport) async {
        if (transport == TransportPush.aucun) {
          await SyncArrierePlanService.instance.demarrer();
        } else {
          await SyncArrierePlanService.instance.arreter();
        }
      }).catchError((Object e) {
        debugPrint('Push: démarrage impossible (on continue): $e');
      }),
    );
  }

  /// Username Matrix unique et valide dérivé de l'ID Supabase.
  String _matrixUsername(String userId) => 'u_${userId.replaceAll('-', '')}';

  /// Vérifie que [motDePasse] est bien celui du compte.
  ///
  /// Supabase n'offre pas de « vérifier sans changer » : on re-signe donc avec
  /// l'adresse du compte, ce qui échoue si le mot de passe est faux et se
  /// contente de rafraîchir la session sinon. Volontairement `_client.auth`
  /// plutôt que [signIn], pour ne pas relancer toute la mise en place Matrix.
  Future<bool> verifierMotDePasse(String motDePasse) async {
    final email = currentUser?.email;
    if (email == null) return false;
    try {
      await _client.auth.signInWithPassword(
        email: email,
        password: motDePasse,
      );
      return true;
    } on AuthException {
      return false;
    }
  }

  /// Mot de passe Matrix de l'utilisateur connecté, ou null hors session.
  ///
  /// Aléatoire et jamais montré : il sert aux opérations que le serveur
  /// protège par une ré-authentification, comme fermer une session à distance.
  /// À ne pas confondre avec le mot de passe Supabase, que l'utilisateur
  /// choisit et qui sert de phrase secrète SSSS.
  Future<String?> motDePasseMatrix() async {
    final userId = currentUser?.id;
    if (userId == null) return null;
    return _getOrCreateMatrixPassword(userId);
  }

  /// Récupère, ou génère puis persiste, le mot de passe Matrix de l'utilisateur.
  ///
  /// Le cache local est sauté dans un navigateur, et c'est délibéré :
  /// `flutter_secure_storage` y refuse de fonctionner hors contexte sécurisé
  /// (« only works in secure contexts »), ce qui faisait échouer toute la
  /// session Matrix sur une page servie en HTTP. Même en HTTPS on s'en
  /// passerait : sur le web il ne fait que chiffrer avec une clé rangée dans
  /// le `localStorage` d'à côté, ce qui protège peu. Supabase reste la source
  /// de vérité, sous RLS, et une relecture par session ne coûte rien.
  Future<String> _getOrCreateMatrixPassword(String userId) async {
    const storage = FlutterSecureStorage();
    final storageKey = 'matrix_password_$userId';

    // 1. Cache local (cet appareil)
    final cached = estWeb ? null : await storage.read(key: storageKey);
    if (cached != null) return cached;

    // 2. Supabase (autre appareil déjà enregistré)
    final row = await _client
        .from('matrix_credentials')
        .select('matrix_password')
        .eq('user_id', userId)
        .maybeSingle();
    final existing = row?['matrix_password'] as String?;
    if (existing != null) {
      if (!estWeb) await storage.write(key: storageKey, value: existing);
      return existing;
    }

    // 3. Première fois : mot de passe aléatoire, persisté secure storage + Supabase
    final password = _generateSecurePassword();
    await _client.from('matrix_credentials').upsert({
      'user_id': userId,
      'matrix_password': password,
    });
    if (!estWeb) await storage.write(key: storageKey, value: password);
    return password;
  }

  /// Génère un mot de passe aléatoire cryptographiquement sûr.
  String _generateSecurePassword() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// Connexion avec magic link (email)
  Future<void> signInWithMagicLink({required String email}) async {
    await _client.auth.signInWithOtp(
      email: email,
      emailRedirectTo: 'fr.rempart_messenger.app://login-callback',
    );
  }

  /// Connexion avec OAuth (Google, Apple, etc.)
  Future<bool> signInWithOAuth(OAuthProvider provider) {
    return _client.auth.signInWithOAuth(
      provider,
      redirectTo: 'fr.rempart_messenger.app://login-callback',
    );
  }

  /// Déconnexion (Supabase + Matrix)
  Future<void> signOut() async {
    // Déconnexion Matrix
    try {
      await MatrixService.instance.logout();
      debugPrint('Matrix: Déconnecté');
    } catch (e) {
      debugPrint('Matrix logout error: $e');
    }

    // Déconnexion Supabase
    await _client.auth.signOut();
  }

  /// Réinitialisation du mot de passe
  Future<void> resetPassword({required String email}) async {
    await _client.auth.resetPasswordForEmail(
      email,
      redirectTo: 'fr.rempart_messenger.app://reset-callback',
    );
  }

  /// Mise à jour du mot de passe
  Future<UserResponse> updatePassword({required String newPassword}) {
    return _client.auth.updateUser(
      UserAttributes(password: newPassword),
    );
  }

  /// Mise à jour du profil
  Future<UserResponse> updateProfile({
    String? email,
    String? displayName,
    String? avatarUrl,
  }) {
    final data = <String, dynamic>{};
    if (displayName != null) data['display_name'] = displayName;
    if (avatarUrl != null) data['avatar_url'] = avatarUrl;

    return _client.auth.updateUser(
      UserAttributes(
        email: email,
        data: data.isNotEmpty ? data : null,
      ),
    );
  }

  /// Créer le profil utilisateur dans la table profiles
  Future<void> _createUserProfile(
    String userId,
    String email,
    String displayName,
  ) async {
    // Note: email n'est pas stocké dans profiles car déjà dans auth.users
    // username est généré à partir de l'email
    await _client.from('profiles').upsert({
      'id': userId,
      'username': email.split('@').first,
      'display_name': displayName,
    });
  }

  /// Récupérer le profil utilisateur
  Future<Map<String, dynamic>?> getProfile(String userId) async {
    final response =
        await _client.from('profiles').select().eq('id', userId).maybeSingle();
    return response;
  }

  /// Supprimer le compte
  /// Efface définitivement le compte et tout ce qui s'y rattache.
  ///
  /// Le travail se fait côté serveur, dans la gateway : effacer un compte
  /// Supabase demande la clé de service, qui ne doit jamais se trouver dans
  /// une application distribuée. L'app présente son JWT, la gateway fait le
  /// reste (bots, compte Matrix, compte Supabase, avatars).
  ///
  /// La déconnexion locale suit, quoi qu'il arrive ensuite : le compte n'existe
  /// plus, rester connecté dessus n'aurait aucun sens.
  Future<void> deleteAccount() async {
    await BotGatewayService().deleteAccount();
    try {
      await MatrixService.instance.logout();
    } catch (e) {
      debugPrint('Suppression: déconnexion Matrix ignorée ($e)');
    }
    await _client.auth.signOut();
  }
}
