import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/providers/providers.dart';
import '../../../data/services/matrix_service.dart';
import '../../../services/auth_service.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/common/recovery_key_dialog.dart';

/// Changement du mot de passe du compte.
///
/// Ce mot de passe n'en est pas seulement un : il sert aussi de phrase secrète
/// pour le coffre de clés E2E (SSSS), d'où le déroulé en deux temps.
///
/// L'ordre est le point important. On re-chiffre le coffre **avant** de changer
/// le mot de passe Supabase : tant que ce dernier n'a pas bougé, l'ancienne
/// phrase reste celle du compte, donc un échec se rattrape par un simple
/// nouvel essai. Dans l'autre sens, un échec laisserait un compte au nouveau
/// mot de passe et des clés fermées par l'ancien, que l'utilisateur vient
/// d'abandonner : plus rien à retenter, seule la clé de récupération sauverait
/// la mise.
class ChangerMotDePasseScreen extends ConsumerStatefulWidget {
  const ChangerMotDePasseScreen({super.key});

  @override
  ConsumerState<ChangerMotDePasseScreen> createState() =>
      _ChangerMotDePasseScreenState();
}

class _ChangerMotDePasseScreenState
    extends ConsumerState<ChangerMotDePasseScreen> {
  final _actuelController = TextEditingController();
  final _nouveauController = TextEditingController();
  final _confirmationController = TextEditingController();

  bool _enCours = false;

  /// Ce que fait l'app en ce moment, affiché sous le bouton. L'opération dure
  /// plusieurs secondes et touche aux clés : mieux vaut dire où on en est.
  String? _etape;

  String? _erreur;

  @override
  void dispose() {
    _actuelController.dispose();
    _nouveauController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AdaptiveScaffold(
      title: 'Changer le mot de passe',
      previousPageTitle: 'Paramètres',
      body: ListView(
        padding: const EdgeInsets.all(RempartTokens.espaceL),
        children: [
          Container(
            padding: const EdgeInsets.all(RempartTokens.espaceL),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(RempartTokens.rayonCarte),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.key, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: RempartTokens.espaceM),
                Expanded(
                  child: Text(
                    'Votre mot de passe déverrouille aussi vos clés de '
                    'chiffrement. Elles seront re-chiffrées au passage, et une '
                    'nouvelle clé de récupération vous sera montrée : '
                    "l'ancienne ne fonctionnera plus.",
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: RempartTokens.espaceXl),
          AdaptiveTextField(
            controller: _actuelController,
            label: 'Mot de passe actuel',
            obscureText: true,
            enabled: !_enCours,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: RempartTokens.espaceL),
          AdaptiveTextField(
            controller: _nouveauController,
            label: 'Nouveau mot de passe',
            helperText: 'Au moins ${AppConstants.minPasswordLength} caractères, '
                'avec un chiffre et une minuscule',
            obscureText: true,
            enabled: !_enCours,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: RempartTokens.espaceL),
          AdaptiveTextField(
            controller: _confirmationController,
            label: 'Confirmer le nouveau mot de passe',
            obscureText: true,
            enabled: !_enCours,
            onSubmitted: (_) => _enCours ? null : _changer(),
          ),
          if (_erreur != null) ...[
            const SizedBox(height: RempartTokens.espaceL),
            Text(
              _erreur!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: RempartTokens.espaceXl),
          AdaptiveButton(
            onPressed: _enCours ? null : _changer,
            isLoading: _enCours,
            child: const Text('Changer le mot de passe'),
          ),
          if (_etape != null) ...[
            const SizedBox(height: RempartTokens.espaceM),
            Text(
              _etape!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  /// Règles alignées sur l'inscription : un mot de passe refusé à la création
  /// ne doit pas devenir acceptable en le changeant.
  String? _valider(String nouveau, String confirmation) {
    if (nouveau.length < AppConstants.minPasswordLength) {
      return 'Le nouveau mot de passe doit contenir au moins '
          '${AppConstants.minPasswordLength} caractères';
    }
    if (!nouveau.contains(RegExp('[0-9]'))) {
      return 'Le nouveau mot de passe doit contenir au moins un chiffre';
    }
    if (!nouveau.contains(RegExp('[a-z]'))) {
      return 'Le nouveau mot de passe doit contenir au moins une minuscule';
    }
    if (nouveau != confirmation) {
      return 'Les deux saisies ne correspondent pas';
    }
    return null;
  }

  Future<void> _changer() async {
    final actuel = _actuelController.text;
    final nouveau = _nouveauController.text;

    final probleme = _valider(nouveau, _confirmationController.text);
    if (probleme != null) {
      setState(() => _erreur = probleme);
      return;
    }
    if (actuel == nouveau) {
      setState(() => _erreur = 'Le nouveau mot de passe est identique à '
          "l'actuel");
      return;
    }

    setState(() {
      _enCours = true;
      _erreur = null;
      _etape = 'Vérification du mot de passe actuel…';
    });

    final auth = ref.read(authServiceProvider);
    final matrix = ref.read(matrixServiceProvider);

    try {
      if (!await auth.verifierMotDePasse(actuel)) {
        _echouer('Mot de passe actuel incorrect');
        return;
      }

      final motDePasseMatrix = await auth.motDePasseMatrix();
      if (motDePasseMatrix == null) {
        _echouer('Session Matrix introuvable, reconnectez-vous');
        return;
      }

      // 1. Le coffre de clés d'abord. S'il résiste, on s'arrête ici : le compte
      // n'a pas bougé, l'utilisateur peut retenter avec le même mot de passe.
      setState(() => _etape = 'Re-chiffrement de vos clés…');
      String? cleARetenir;
      try {
        cleARetenir = await matrix.rechiffrerSsss(
          actuel,
          nouveau,
          motDePasseMatrix,
        );
      } catch (e) {
        debugPrint('Mot de passe: re-chiffrement SSSS échoué: $e');
        _echouer(
          "Vos clés de chiffrement n'ont pas pu être re-chiffrées. Le mot de "
          "passe n'a pas été changé, vous pouvez réessayer.",
        );
        return;
      }

      // 2. Le compte ensuite. Un seul appel réseau, mais s'il rate on remet le
      // coffre sur l'ancienne phrase pour revenir exactement à l'état initial.
      setState(() => _etape = 'Enregistrement du nouveau mot de passe…');
      try {
        await auth.updatePassword(newPassword: nouveau);
      } catch (e) {
        debugPrint('Mot de passe: changement Supabase échoué: $e');
        final cleApresRetour = await _revenirEnArriere(
          matrix,
          nouveau,
          actuel,
          motDePasseMatrix,
        );
        if (cleApresRetour != null) {
          // Retour en arrière réussi : le coffre est de nouveau sur l'ancien
          // mot de passe, mais sa clé de récupération a changé au passage.
          await _montrerCle(cleApresRetour);
          _echouer(
            "Le mot de passe n'a pas pu être changé. Rien n'a bougé, mais "
            'notez la nouvelle clé de récupération affichée.',
          );
        } else {
          // Ni l'un ni l'autre : le coffre est sur le nouveau mot de passe,
          // que le compte ne connaît pas. La clé affichée est la seule issue.
          await _montrerCle(cleARetenir);
          _echouer(
            "Le mot de passe n'a pas pu être changé, mais vos clés sont "
            'passées sur le nouveau. Conservez la clé de récupération '
            'affichée et réessayez le changement.',
          );
        }
        return;
      }

      await _montrerCle(cleARetenir);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mot de passe changé')),
      );
      await Navigator.of(context).maybePop();
    } catch (e) {
      _echouer('Changement impossible : $e');
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  /// Remet le coffre sur [cible] après un changement de compte manqué. Rend la
  /// nouvelle clé de récupération, ou null si le retour a échoué lui aussi.
  Future<String?> _revenirEnArriere(
    MatrixService matrix,
    String depuis,
    String cible,
    String motDePasseMatrix,
  ) async {
    if (mounted) {
      setState(() => _etape = 'Retour en arrière sur vos clés…');
    }
    try {
      return await matrix.rechiffrerSsss(depuis, cible, motDePasseMatrix);
    } catch (e) {
      debugPrint('Mot de passe: retour en arrière SSSS échoué: $e');
      return null;
    }
  }

  Future<void> _montrerCle(String? cle) async {
    if (cle == null || !mounted) return;
    await showRecoveryKeyDialog(context, cle);
  }

  void _echouer(String message) {
    if (!mounted) return;
    setState(() {
      _erreur = message;
      _etape = null;
    });
  }
}
