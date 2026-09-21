import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../services/auth_service.dart';
import '../../widgets/adaptive/adaptive.dart';

/// Première étape d'un mot de passe oublié : recevoir le lien par courriel.
///
/// L'écran dit tout de suite ce qui se joue, parce que la suite ne se rattrape
/// pas : le mot de passe de Rempart ouvre aussi le coffre de clés, et qui ne
/// peut plus l'ouvrir perd ses anciens messages. Mieux vaut que la personne
/// aille chercher sa clé de récupération maintenant, pendant qu'elle lit, que
/// trois écrans plus loin devant un champ qu'elle ne sait pas remplir.
class MotDePasseOublieScreen extends ConsumerStatefulWidget {
  const MotDePasseOublieScreen({super.key});

  @override
  ConsumerState<MotDePasseOublieScreen> createState() =>
      _MotDePasseOublieScreenState();
}

class _MotDePasseOublieScreenState
    extends ConsumerState<MotDePasseOublieScreen> {
  final _emailController = TextEditingController();

  bool _enCours = false;
  bool _envoye = false;
  String? _erreur;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _envoyer() async {
    final email = _emailController.text.trim();
    if (!email.contains('@')) {
      setState(() => _erreur = 'Entrez une adresse électronique valide');
      return;
    }

    setState(() {
      _enCours = true;
      _erreur = null;
    });

    try {
      await ref.read(authServiceProvider).resetPassword(email: email);
      if (!mounted) return;
      setState(() => _envoye = true);
    } catch (e) {
      debugPrint('Mot de passe oublié : envoi échoué ($e)');
      if (!mounted) return;
      setState(() {
        // On ne dit pas si l'adresse existe : ce serait un moyen commode de
        // savoir qui a un compte ici.
        _erreur = "Le message n'a pas pu être envoyé. Réessayez dans un "
            'moment.';
      });
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AdaptiveScaffold(
      title: 'Mot de passe oublié',
      previousPageTitle: 'Connexion',
      body: ListView(
        padding: const EdgeInsets.all(RempartTokens.espaceL),
        children: [
          if (_envoye) ...[
            _Encart(
              icone: Icons.mark_email_read_outlined,
              couleur: RempartTokens.texteSucces(theme.brightness),
              texte: 'Si un compte existe à cette adresse, un lien vient de '
                  'lui être envoyé. Ouvrez-le depuis ce téléphone : il ramène '
                  'ici pour choisir un nouveau mot de passe.',
            ),
            const SizedBox(height: RempartTokens.espaceXl),
            AdaptiveButton(
              onPressed: () => context.go('/login'),
              child: const Text('Revenir à la connexion'),
            ),
          ] else ...[
            _Encart(
              icone: Icons.key_outlined,
              couleur: theme.colorScheme.primary,
              texte: 'Votre mot de passe ouvre aussi le coffre qui garde vos '
                  'clés de déchiffrement. Préparez votre clé de récupération, '
                  'celle qui vous a été montrée à la création du compte : elle '
                  "vous sera demandée à l'étape suivante, et c'est elle qui "
                  'sauve vos anciens messages.',
            ),
            const SizedBox(height: RempartTokens.espaceM),
            Text(
              'Sans elle, vous retrouverez votre compte et vos conversations, '
              "mais les messages reçus avant aujourd'hui resteront fermés.",
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: RempartTokens.espaceXl),
            AdaptiveTextField(
              controller: _emailController,
              label: 'Adresse électronique',
              keyboardType: TextInputType.emailAddress,
              enabled: !_enCours,
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
              onPressed: _enCours ? null : _envoyer,
              child: Text(_enCours ? 'Envoi…' : 'Recevoir le lien'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bloc d'explication en tête d'écran, teinté de la couleur du propos.
class _Encart extends StatelessWidget {
  const _Encart({
    required this.icone,
    required this.couleur,
    required this.texte,
  });

  final IconData icone;
  final Color couleur;
  final String texte;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(RempartTokens.espaceL),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(RempartTokens.rayonCarte),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 20, color: couleur),
          const SizedBox(width: RempartTokens.espaceM),
          Expanded(child: Text(texte, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
