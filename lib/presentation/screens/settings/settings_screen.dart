import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/plateforme.dart';
import '../../../data/providers/contenu_notifications.dart';
import '../../../data/providers/providers.dart';
import '../../../data/services/notification_service.dart';
import '../../../services/auth_service.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/common/user_avatar.dart';
import '../../widgets/settings/mise_a_jour.dart';
import '../../widgets/settings/push_mode_tile.dart';
import '../../widgets/settings/soutien.dart';
import '../../widgets/settings/taille_texte_tile.dart';
import '../../widgets/settings/veille_batterie_tile.dart';

/// Écran des paramètres utilisateur
/// Utilise Cupertino sur iOS et Material sur Android
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authService = ref.watch(authServiceProvider);
    final user = authService.currentUser;
    final matrixService = ref.watch(matrixServiceProvider);

    // Le profil Supabase d'abord, les metadonnees d'authentification ensuite.
    // Ces metadonnees sont posees a l'inscription et **plus jamais mises a
    // jour** : les lire seules faisait afficher ici l'ancien nom, pour
    // toujours, alors que « Modifier le profil » ecrit bien dans la table des
    // profils (et sur Matrix). Meme ordre que l'ecran Profil.
    final profil = ref.watch(currentProfileProvider).value;
    final displayName = profil?.name ??
        user?.userMetadata?['display_name'] as String? ??
        'Utilisateur';
    // La photo n'était jamais affichée ici : l'en-tête se contentait de
    // l'initiale, alors que le profil porte bien une URL d'avatar.
    final avatarUrl = profil?.avatarUrl;
    final email = user?.email ?? '';
    final matrixId = matrixService.currentUserId ?? 'Non connecté';

    if (estIOS) {
      return _buildCupertinoSettings(
        context,
        ref,
        displayName,
        avatarUrl,
        email,
        matrixId,
        matrixService.client?.encryptionEnabled ?? false,
      );
    } else {
      return _buildMaterialSettings(
        context,
        ref,
        displayName,
        avatarUrl,
        email,
        matrixId,
        matrixService.client?.encryptionEnabled ?? false,
      );
    }
  }

  // ============================================
  // Version Cupertino (iOS)
  // ============================================

  Widget _buildCupertinoSettings(
    BuildContext context,
    WidgetRef ref,
    String displayName,
    String? avatarUrl,
    String email,
    String matrixId,
    bool chiffrementActif,
  ) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Paramètres'),
      ),
      child: SafeArea(
        child: ListView(
          children: [
            // Section Profil
            _buildProfileSection(
              context,
              displayName,
              avatarUrl,
              email,
              matrixId,
            ),

            // Section Compte
            CupertinoListSection.insetGrouped(
              backgroundColor: Colors.transparent,
              decoration: _decorationSection(context),
              header: const Text('COMPTE'),
              children: [
                CupertinoListTile.notched(
                  leading: const Icon(CupertinoIcons.person),
                  title: const Text('Modifier le profil'),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () => context.push('/profil/modifier'),
                ),
                CupertinoListTile.notched(
                  leading: const Icon(CupertinoIcons.lock),
                  title: const Text('Changer le mot de passe'),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () => context.push('/settings/mot-de-passe'),
                ),
              ],
            ),

            // Section Conversations
            CupertinoListSection.insetGrouped(
              backgroundColor: Colors.transparent,
              decoration: _decorationSection(context),
              header: const Text('CONVERSATIONS'),
              children: [
                // Widget Material dans une liste Cupertino : enveloppé, sinon
                // il peint sans Material ancêtre et lève à l'affichage.
                const Material(
                  color: Colors.transparent,
                  child: TailleTexteTile(),
                ),
                CupertinoListTile.notched(
                  leading: const Icon(CupertinoIcons.archivebox),
                  title: const Text('Archives'),
                  subtitle: const Text('Conversations mises de côté'),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () => context.push('/archives'),
                ),
              ],
            ),

            // Section Bots
            CupertinoListSection.insetGrouped(
              backgroundColor: Colors.transparent,
              decoration: _decorationSection(context),
              header: const Text('BOTS'),
              children: [
                CupertinoListTile.notched(
                  leading: const Icon(CupertinoIcons.desktopcomputer),
                  title: const Text('Mes bots'),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () => context.push('/my-bots'),
                ),
              ],
            ),

            // Section Notifications
            CupertinoListSection.insetGrouped(
              backgroundColor: Colors.transparent,
              decoration: _decorationSection(context),
              header: const Text('NOTIFICATIONS'),
              children: [
                CupertinoListTile.notched(
                  leading: const Icon(CupertinoIcons.bell),
                  title: const Text('Notifications push'),
                  trailing: CupertinoSwitch(
                    value: true,
                    onChanged: (value) => _showNotImplemented(context),
                  ),
                ),
                CupertinoListTile.notched(
                  leading: const Icon(CupertinoIcons.eye_slash),
                  title: const Text('Contenu des messages'),
                  subtitle: const Text(
                    'Afficher le texte dans les notifications. Désactivé, '
                    'elles se réduisent à « Nouveau message ».',
                  ),
                  trailing: CupertinoSwitch(
                    value: ref.watch(contenuNotificationsProvider),
                    onChanged: (value) => _changerContenu(ref, value: value),
                  ),
                ),
                CupertinoListTile.notched(
                  leading: const Icon(CupertinoIcons.speaker_2),
                  title: const Text('Sons'),
                  trailing: CupertinoSwitch(
                    value: true,
                    onChanged: (value) => _showNotImplemented(context),
                  ),
                ),
              ],
            ),

            // Section Confidentialité
            CupertinoListSection.insetGrouped(
              backgroundColor: Colors.transparent,
              decoration: _decorationSection(context),
              header: const Text('CONFIDENTIALITÉ & SÉCURITÉ'),
              children: [
                CupertinoListTile.notched(
                  leading: const Icon(CupertinoIcons.shield),
                  title: const Text('Chiffrement E2E'),
                  additionalInfo: Text(
                    chiffrementActif ? 'Actif' : 'Inactif',
                    style: TextStyle(
                      color: chiffrementActif
                          ? CupertinoColors.activeGreen
                          : CupertinoColors.systemOrange,
                    ),
                  ),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () => _showEncryptionInfoCupertino(context),
                ),
                CupertinoListTile.notched(
                  leading: const Icon(CupertinoIcons.nosign),
                  title: const Text('Personnes bloquées'),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () => context.push('/settings/bloques'),
                ),
                CupertinoListTile.notched(
                  leading: const Icon(CupertinoIcons.device_phone_portrait),
                  title: const Text('Appareils connectés'),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () => context.push('/settings/appareils'),
                ),
              ],
            ),

            // Section À propos
            CupertinoListSection.insetGrouped(
              backgroundColor: Colors.transparent,
              decoration: _decorationSection(context),
              header: const Text('À PROPOS'),
              children: [
                CupertinoListTile.notched(
                  leading: const Icon(CupertinoIcons.info),
                  title: const Text('Version'),
                  additionalInfo: FutureBuilder<String>(
                    future: versionInstallee(),
                    builder: (context, snapshot) =>
                        Text(snapshot.data ?? '...'),
                  ),
                ),
                // Le don ne s'affiche que si une page existe pour l'accueillir
                // (`DON_URL`). Sur iOS il n'y a pas de mise à jour à proposer
                // au-dessus : Apple interdit l'installation hors magasin.
                if (AppConstants.donDisponible)
                  CupertinoListTile.notched(
                    leading: const Icon(CupertinoIcons.heart),
                    title: const Text('Soutenir Rempart'),
                    trailing: const CupertinoListTileChevron(),
                    onTap: () => ouvrirPageDeSoutien(context),
                  ),
                CupertinoListTile.notched(
                  leading: const Icon(CupertinoIcons.doc_text),
                  title: const Text("Conditions d'utilisation"),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () => context.push('/legal/conditions'),
                ),
                CupertinoListTile.notched(
                  leading: const Icon(CupertinoIcons.hand_raised),
                  title: const Text('Politique de confidentialité'),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () => context.push('/legal/confidentialite'),
                ),
                CupertinoListTile.notched(
                  leading: const Icon(
                      CupertinoIcons.chevron_left_slash_chevron_right),
                  title: const Text('Code source et licences'),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () => context.push('/legal/licences'),
                ),
              ],
            ),

            // Section Actions
            CupertinoListSection.insetGrouped(
              backgroundColor: Colors.transparent,
              decoration: _decorationSection(context),
              children: [
                CupertinoListTile.notched(
                  leading: const Icon(
                    CupertinoIcons.square_arrow_right,
                    color: CupertinoColors.destructiveRed,
                  ),
                  title: const Text(
                    'Déconnexion',
                    style: TextStyle(color: CupertinoColors.destructiveRed),
                  ),
                  onTap: () => _confirmLogoutCupertino(context, ref),
                ),
              ],
            ),

            // Supprimer le compte
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: CupertinoButton(
                onPressed: () => _supprimerCompte(context, ref),
                child: Text(
                  'Supprimer mon compte',
                  style: TextStyle(
                    color:
                        CupertinoColors.destructiveRed.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEncryptionInfoCupertino(BuildContext context) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Chiffrement de bout en bout'),
        content: const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text(
            'Tous vos messages sont chiffrés de bout en bout grâce au protocole Matrix.\n\n'
            'Cela signifie que seuls vous et vos correspondants pouvez lire vos messages. '
            'Même les serveurs Rempart ne peuvent pas les déchiffrer.',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('Compris'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogoutCupertino(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Déconnexion'),
        content: const Text('Voulez-vous vraiment vous déconnecter ?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Déconnexion'),
          ),
        ],
      ),
    );

    if ((confirmed ?? false) && context.mounted) {
      final matrixService = ref.read(matrixServiceProvider);
      await matrixService.logout();

      final authService = ref.read(authServiceProvider);
      await authService.signOut();

      if (context.mounted) {
        context.go('/login');
      }
    }
  }

  /// Efface le compte, pour de bon.
  ///
  /// Les deux boutiques d'applications exigent que la suppression soit
  /// possible **depuis l'application**, et pas seulement sur demande au
  /// support. Le travail se fait côté serveur : bots, compte Matrix, compte
  /// Supabase et avatars.
  ///
  /// Deux confirmations, dont la seconde énumère ce qui disparaît : rien ici
  /// n'est rattrapable, et la première frappe est souvent distraite.
  Future<void> _supprimerCompte(BuildContext context, WidgetRef ref) async {
    final premier = await showAdaptiveAlert<bool>(
      context: context,
      title: 'Supprimer le compte',
      content: 'Votre compte, vos bots et votre profil seront effacés. '
          'Cette action est irréversible.',
      cancelText: 'Annuler',
      confirmText: 'Continuer',
      isDestructive: true,
    );
    if (premier != true || !context.mounted) return;

    final second = await showAdaptiveAlert<bool>(
      context: context,
      title: 'Confirmer la suppression',
      content: "Vous perdrez l'accès à vos conversations et à vos clés de "
          'chiffrement. Les messages déjà reçus par vos correspondants restent '
          'sur leurs appareils : ils ne peuvent pas en être retirés.',
      cancelText: 'Annuler',
      confirmText: 'Supprimer définitivement',
      isDestructive: true,
    );
    if (second != true || !context.mounted) return;

    // Barrière modale : l'opération traverse trois services et dure quelques
    // secondes ; rien ne doit être touché entre-temps.
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      ),
    );

    try {
      await ref.read(authServiceProvider).deleteAccount();
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      context.go('/login');
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await showAdaptiveAlert<void>(
        context: context,
        title: 'Suppression impossible',
        content: "Le compte n'a pas été supprimé : $e\n\nRéessayez, ou "
            'écrivez à j.demory@proton.me.',
        confirmText: 'Fermer',
      );
    }
  }

  // ============================================
  // Version Material (Android)
  // ============================================

  Widget _buildMaterialSettings(
    BuildContext context,
    WidgetRef ref,
    String displayName,
    String? avatarUrl,
    String email,
    String matrixId,
    bool chiffrementActif,
  ) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
      ),
      body: ListView(
        children: [
          // Section Profil
          _buildProfileSection(
            context,
            displayName,
            avatarUrl,
            email,
            matrixId,
          ),

          const Divider(),

          // Section Compte
          _buildSectionHeader(context, 'Compte'),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Modifier le profil'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/profil/modifier'),
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Changer le mot de passe'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/mot-de-passe'),
          ),

          const Divider(),

          // Section Conversations
          _buildSectionHeader(context, 'Conversations'),
          const TailleTexteTile(),
          ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: const Text('Archives'),
            subtitle: const Text('Conversations mises de côté'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/archives'),
          ),

          const Divider(),

          // Section Bots
          _buildSectionHeader(context, 'Bots'),
          ListTile(
            leading: const Icon(Icons.smart_toy_outlined),
            title: const Text('Mes bots'),
            subtitle: const Text('Créer et configurer vos propres bots'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/my-bots'),
          ),

          const Divider(),

          // Section Notifications
          _buildSectionHeader(context, 'Notifications'),
          const PushModeTile(),
          const VeilleBatterieTile(),
          SwitchListTile(
            secondary: const Icon(Icons.visibility_off_outlined),
            title: const Text('Contenu des messages'),
            subtitle: const Text(
              'Afficher le texte dans les notifications. Désactivé, elles se '
              'réduisent à « Nouveau message ».',
            ),
            value: ref.watch(contenuNotificationsProvider),
            onChanged: (value) => _changerContenu(ref, value: value),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.volume_up_outlined),
            title: const Text('Sons'),
            subtitle: const Text('Jouer un son pour les messages'),
            value: true,
            onChanged: (value) => _showNotImplemented(context),
          ),

          const Divider(),

          // Section Confidentialité
          _buildSectionHeader(context, 'Confidentialité & Sécurité'),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('Chiffrement E2E'),
            subtitle: Text(
              chiffrementActif ? 'Actif' : 'Inactif',
              style: TextStyle(
                color: chiffrementActif
                    ? RempartTokens.texteSucces(Theme.of(context).brightness)
                    : RempartTokens.texteAlerte(Theme.of(context).brightness),
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showEncryptionInfoMaterial(context),
          ),
          ListTile(
            leading: const Icon(Icons.block_outlined),
            title: const Text('Personnes bloquées'),
            subtitle: const Text('Gérer qui ne peut plus vous écrire'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/bloques'),
          ),
          ListTile(
            leading: const Icon(Icons.devices_outlined),
            title: const Text('Appareils connectés'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/appareils'),
          ),

          const Divider(),

          // Section À propos
          _buildSectionHeader(context, 'À propos'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Version'),
            subtitle: FutureBuilder<String>(
              future: versionInstallee(),
              builder: (context, snapshot) => Text(snapshot.data ?? '...'),
            ),
          ),
          const MiseAJourTile(),
          if (AppConstants.donDisponible)
            ListTile(
              leading: const Icon(Icons.favorite_outline),
              title: const Text('Soutenir Rempart'),
              subtitle: const Text('Rempart est gratuit et sans publicité'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => ouvrirPageDeSoutien(context),
            ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text("Conditions d'utilisation"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/legal/conditions'),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Politique de confidentialité'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/legal/confidentialite'),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('Code source et licences'),
            subtitle: const Text('Logiciel libre, sous licence AGPL'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/legal/licences'),
          ),

          const Divider(),

          // Déconnexion
          ListTile(
            leading: Icon(Icons.logout, color: theme.colorScheme.error),
            title: Text(
              'Déconnexion',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            onTap: () => _confirmLogoutMaterial(context, ref),
          ),

          const SizedBox(height: 32),

          // Supprimer le compte
          Center(
            child: TextButton(
              onPressed: () => _supprimerCompte(context, ref),
              child: Text(
                'Supprimer mon compte',
                style: TextStyle(
                  color: theme.colorScheme.error.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _showEncryptionInfoMaterial(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.shield_outlined, size: 48),
        title: const Text('Chiffrement de bout en bout'),
        content: const Text(
          'Tous vos messages sont chiffrés de bout en bout grâce au protocole Matrix.\n\n'
          'Cela signifie que seuls vous et vos correspondants pouvez lire vos messages. '
          'Même les serveurs Rempart ne peuvent pas les déchiffrer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Compris'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogoutMaterial(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.logout),
        title: const Text('Déconnexion'),
        content: const Text('Voulez-vous vraiment vous déconnecter ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Déconnexion'),
          ),
        ],
      ),
    );

    if ((confirmed ?? false) && context.mounted) {
      final matrixService = ref.read(matrixServiceProvider);
      await matrixService.logout();

      final authService = ref.read(authServiceProvider);
      await authService.signOut();

      if (context.mounted) {
        context.go('/login');
      }
    }
  }

  // ============================================
  // Widgets partagés
  // ============================================

  /// Habillage d'une section de réglages, aux jetons du design système.
  ///
  /// `CupertinoListSection` peint sinon ses propres gris système : en sombre,
  /// un fond NOIR pur qui tranchait avec le bleu nuit de l'application, et une
  /// couture visible juste sous l'en-tête.
  static BoxDecoration _decorationSection(BuildContext context) {
    final couleurs = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: couleurs.surface,
      borderRadius: BorderRadius.circular(RempartTokens.rayonCarte),
      border: Border.all(color: couleurs.outlineVariant),
    );
  }

  Widget _buildProfileSection(
    BuildContext context,
    String displayName,
    String? avatarUrl,
    String email,
    String matrixId,
  ) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Avatar : la photo du profil, ou l'initiale à défaut. `UserAvatar`
          // tient déjà les deux cas, et c'est lui qu'affichent les listes de
          // contacts : le même visage partout.
          UserAvatar(name: displayName, imageUrl: avatarUrl, size: 100),
          const SizedBox(height: 16),

          // Nom
          Text(
            displayName,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),

          // Email
          Text(
            email,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),

          // Identifiant Matrix : jamais montré, seulement copiable. Tronqué
          // il ne renseignait personne, entier il occupait deux lignes pour
          // dire ce que l'e-mail juste au-dessus dit déjà en clair.
          _MatrixIdChip(matrixId: matrixId, color: primaryColor),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  /// Applique le choix tout de suite au service, puis l'enregistre.
  ///
  /// Le service vit hors de Riverpod : sans cette recopie, le réglage
  /// n'agirait qu'au prochain lancement, quand `main.dart` le relit.
  void _changerContenu(WidgetRef ref, {required bool value}) {
    ref.read(contenuNotificationsProvider.notifier).state = value;
    NotificationService.instance.afficherContenu = value;
    unawaited(enregistrerContenuNotifications(afficher: value));
  }

  void _showNotImplemented(BuildContext context) {
    if (estIOS) {
      showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Bientôt disponible'),
          content: const Text('Cette fonctionnalité sera bientôt disponible'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cette fonctionnalité sera bientôt disponible'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
}

/// Chip du Matrix ID.
///
/// Le mxid complet (`@u_<uuid>:<domaine>`, ~47 caractères) déborde de la
/// largeur disponible : on n'en affiche qu'un extrait, et un appui copie
/// l'identifiant **entier** dans le presse-papiers. Le retour visuel est géré
/// en interne (pas de ScaffoldMessenger : absent du scaffold Cupertino).
class _MatrixIdChip extends StatefulWidget {
  const _MatrixIdChip({required this.matrixId, required this.color});

  final String matrixId;
  final Color color;

  @override
  State<_MatrixIdChip> createState() => _MatrixIdChipState();
}

class _MatrixIdChipState extends State<_MatrixIdChip> {
  bool _copie = false;
  Timer? _resetTimer;

  /// Vrai mxid (et non le libellé de repli "Non connecté") : seul cas où la
  /// copie a du sens.
  bool get _estMxid => widget.matrixId.startsWith('@');

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _copier() async {
    await Clipboard.setData(ClipboardData(text: widget.matrixId));
    if (!mounted) return;
    setState(() => _copie = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copie = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isIOS = estIOS;

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isIOS ? CupertinoIcons.at : Icons.alternate_email,
            size: 16,
            color: widget.color,
          ),
          const SizedBox(width: 4),
          Text(
            _copie
                ? 'Copié !'
                : _estMxid
                    ? 'Copier mon identifiant Matrix'
                    : widget.matrixId,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: widget.color),
          ),
          if (_estMxid) ...[
            const SizedBox(width: 6),
            Icon(
              _copie
                  ? (isIOS ? CupertinoIcons.checkmark_alt : Icons.check)
                  : (isIOS ? CupertinoIcons.doc_on_doc : Icons.copy_rounded),
              size: 14,
              color: widget.color,
            ),
          ],
        ],
      ),
    );

    if (!_estMxid) return chip;

    return Semantics(
      button: true,
      label: 'Copier mon identifiant Matrix',
      child: GestureDetector(onTap: _copier, child: chip),
    );
  }
}
