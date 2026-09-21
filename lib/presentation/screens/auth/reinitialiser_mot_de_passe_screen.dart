import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../data/providers/providers.dart';
import '../../../data/services/reinitialisation_e2e.dart';
import '../../../services/auth_service.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/common/recovery_key_dialog.dart';

/// Second temps d'un mot de passe oublié : le lien du courriel ouvre cet
/// écran, une session de récupération en poche.
///
/// Deux voies, et l'écran ne cache pas ce qui les sépare :
///
/// - **avec la clé de récupération**, le coffre est rouvert puis refermé sur
///   le nouveau mot de passe. Les secrets sont migrés, donc la sauvegarde de
///   clés reste lisible et les anciens messages aussi ;
/// - **sans elle**, le coffre est effacé et recréé. Le compte et les
///   conversations reviennent, mais tout ce qui a été reçu avant devient
///   illisible pour toujours. Cela se dit avant, en toutes lettres, et se
///   confirme une seconde fois.
///
/// L'ordre des deux opérations est délibéré : le mot de passe du compte
/// d'abord, le coffre ensuite. La session de récupération ne vaut qu'une fois
/// et pour quelques minutes ; si le coffre résistait, quelqu'un qui aurait
/// commencé par lui se retrouverait sans compte utilisable et sans second
/// essai. Dans cet ordre, il garde au moins l'accès à son compte, et peut
/// recommencer.
class ReinitialiserMotDePasseScreen extends ConsumerStatefulWidget {
  const ReinitialiserMotDePasseScreen({super.key});

  @override
  ConsumerState<ReinitialiserMotDePasseScreen> createState() =>
      _ReinitialiserMotDePasseScreenState();
}

class _ReinitialiserMotDePasseScreenState
    extends ConsumerState<ReinitialiserMotDePasseScreen> {
  final _nouveauController = TextEditingController();
  final _confirmationController = TextEditingController();
  final _cleController = TextEditingController();

  /// L'utilisateur déclare ne plus avoir sa clé de récupération.
  bool _sansCle = false;

  bool _enCours = false;
  String? _etape;
  String? _erreur;

  @override
  void dispose() {
    _nouveauController.dispose();
    _confirmationController.dispose();
    _cleController.dispose();
    super.dispose();
  }

  String? _valider() {
    final nouveau = _nouveauController.text;
    if (nouveau.length < 8) {
      return 'Le mot de passe doit faire au moins 8 caractères';
    }
    if (nouveau != _confirmationController.text) {
      return 'Les deux mots de passe ne correspondent pas';
    }
    if (!_sansCle && _cleController.text.trim().isEmpty) {
      return 'Entrez votre clé de récupération, ou indiquez que vous ne '
          "l'avez plus";
    }
    return null;
  }

  /// Deuxième confirmation avant de renoncer à l'historique.
  ///
  /// Une case cochée se coche vite ; ce qu'elle emporte ne revient pas.
  Future<bool> _confirmerLaPerte() async {
    final reponse = await showAdaptiveAlert<bool>(
      context: context,
      title: 'Renoncer aux anciens messages ?',
      content: 'Sans votre clé de récupération, les messages reçus avant '
          "aujourd'hui ne pourront plus être déchiffrés, sur aucun de vos "
          'appareils, et disparaîtront de vos conversations.\n\n'
          'Vos conversations, vos contacts et vos groupes restent en place, et '
          'tout ce qui arrivera ensuite sera lisible normalement.',
      cancelText: 'Annuler',
      confirmText: "J'ai compris, continuer",
      isDestructive: true,
    );
    return reponse ?? false;
  }

  Future<void> _reinitialiser() async {
    final probleme = _valider();
    if (probleme != null) {
      setState(() => _erreur = probleme);
      return;
    }
    if (_sansCle && !await _confirmerLaPerte()) return;
    if (!mounted) return;

    final nouveau = _nouveauController.text;
    final auth = ref.read(authServiceProvider);
    final matrix = ref.read(matrixServiceProvider);

    setState(() {
      _enCours = true;
      _erreur = null;
      _etape = 'Enregistrement du nouveau mot de passe…';
    });

    try {
      await auth.updatePassword(newPassword: nouveau);
    } catch (e) {
      debugPrint('Réinitialisation : mot de passe refusé ($e)');
      _echouer(
        "Le lien a peut-être expiré. Demandez-en un nouveau depuis l'écran de "
        'connexion.',
      );
      return;
    }

    try {
      final utilisateur = auth.currentUser;
      if (utilisateur == null) {
        _echouer('Session perdue. Reconnectez-vous avec votre nouveau mot de '
            'passe.');
        return;
      }

      setState(() => _etape = 'Connexion à la messagerie…');
      await auth.ensureMatrixSession(utilisateur);
      final motDePasseMatrix = await auth.motDePasseMatrix();
      if (motDePasseMatrix == null) {
        _echouer('Session de messagerie introuvable. Reconnectez-vous avec '
            'votre nouveau mot de passe.');
        return;
      }

      setState(() => _etape = _sansCle
          ? "Création d'un coffre de clés neuf…"
          : 'Réouverture de votre coffre de clés…');
      // Posée AVANT le nouveau coffre : si l'opération échoue à mi-chemin, les
      // anciens messages sont déjà perdus, et les afficher n'aurait servi
      // qu'à remplir les conversations d'erreurs de déchiffrement.
      if (_sansCle) await ReinitialisationE2e.marquer();
      final cle = _sansCle
          ? await matrix.reinitialiserChiffrement(nouveau, motDePasseMatrix)
          : await matrix.rouvrirSsssAvec(
              _cleController.text.trim(),
              nouveau,
              motDePasseMatrix,
            );

      if (!mounted) return;
      // Nulle si le SDK n'a pas eu à créer de clé neuve : rien à montrer,
      // l'ancienne reste valable.
      if (cle != null) await showRecoveryKeyDialog(context, cle);
      if (!mounted) return;
      context.go('/home');
    } catch (e) {
      debugPrint('Réinitialisation : coffre de clés ($e)');
      _echouer(
        _sansCle
            ? "Le coffre de clés n'a pas pu être recréé. Votre nouveau mot de "
                'passe fonctionne : reconnectez-vous et réessayez.'
            : "Cette clé de récupération n'ouvre pas votre coffre. Vérifiez-la, "
                "ou indiquez que vous ne l'avez plus.",
      );
    }
  }

  void _echouer(String message) {
    if (!mounted) return;
    setState(() {
      _enCours = false;
      _etape = null;
      _erreur = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AdaptiveScaffold(
      title: 'Nouveau mot de passe',
      body: ListView(
        padding: const EdgeInsets.all(RempartTokens.espaceL),
        children: [
          AdaptiveTextField(
            controller: _nouveauController,
            label: 'Nouveau mot de passe',
            obscureText: true,
            enabled: !_enCours,
          ),
          const SizedBox(height: RempartTokens.espaceM),
          AdaptiveTextField(
            controller: _confirmationController,
            label: 'Confirmer le mot de passe',
            obscureText: true,
            enabled: !_enCours,
          ),
          const SizedBox(height: RempartTokens.espaceXl),
          Text('Vos anciens messages', style: theme.textTheme.titleSmall),
          const SizedBox(height: RempartTokens.espaceS),
          Text(
            'Ils sont chiffrés avec des clés gardées dans un coffre que votre '
            'ancien mot de passe ouvrait. Votre clé de récupération est le '
            "second moyen de l'ouvrir.",
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: RempartTokens.espaceM),
          AdaptiveTextField(
            controller: _cleController,
            label: 'Clé de récupération',
            enabled: !_enCours && !_sansCle,
          ),
          const SizedBox(height: RempartTokens.espaceS),
          AdaptiveSwitchListTile(
            title: const Text("Je n'ai plus ma clé de récupération"),
            subtitle: const Text(
              'Vos conversations reviennent, mais les messages reçus avant '
              "aujourd'hui seront perdus.",
            ),
            value: _sansCle,
            onChanged: _enCours
                ? null
                : (valeur) => setState(() {
                      _sansCle = valeur;
                      _erreur = null;
                    }),
          ),
          if (_erreur != null) ...[
            const SizedBox(height: RempartTokens.espaceM),
            Text(
              _erreur!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: RempartTokens.espaceXl),
          AdaptiveButton(
            onPressed: _enCours ? null : _reinitialiser,
            child: Text(_enCours ? 'Patientez…' : 'Valider'),
          ),
          if (_etape != null) ...[
            const SizedBox(height: RempartTokens.espaceM),
            Text(
              _etape!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
