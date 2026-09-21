import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/supabase_constants.dart';
import '../../../core/plateforme.dart';
import '../../../services/auth_service.dart';
import '../../widgets/common/loading_button.dart';

/// Écran de connexion
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _preRemplirEmail();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  /// Pré-remplit l'email UNIQUEMENT si le build embarque `DEFAULT_LOGIN_EMAIL`
  /// dans son `.env`, et met le curseur sur le mot de passe.
  ///
  /// Confort de test, volontairement pas un comportement par défaut : sans
  /// cette variable (cas d'un `.env` de production), l'écran se comporte comme
  /// avant et rien n'est pré-rempli pour l'utilisateur. Aucun email n'est
  /// mémorisé sur l'appareil.
  void _preRemplirEmail() {
    final email = SupabaseConstants.defaultLoginEmail;
    if (email.isEmpty || _emailController.text.isNotEmpty) return;

    _emailController.text = email;
    _passwordFocus.requestFocus();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = ref.read(authServiceProvider);
      await authService.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (mounted) {
        context.go('/home');
      }
    } catch (e) {
      setState(() {
        _errorMessage = _getErrorMessage(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _getErrorMessage(dynamic error) {
    final message = error.toString().toLowerCase();
    if (message.contains('invalid login credentials')) {
      return 'Email ou mot de passe incorrect';
    }
    if (message.contains('email not confirmed')) {
      return 'Veuillez confirmer votre email';
    }
    if (message.contains('too many requests')) {
      return 'Trop de tentatives. Réessayez plus tard.';
    }
    if (message.contains('socketexception') ||
        message.contains('cleartext') ||
        message.contains('failed host lookup') ||
        message.contains('connection') ||
        message.contains('clientexception') ||
        message.contains('timeout')) {
      return 'Serveur injoignable. Vérifiez votre connexion.';
    }
    return 'Une erreur est survenue. Réessayez.';
  }

  @override
  Widget build(BuildContext context) {
    return _buildEcran(context);
  }

  /// L'écran, identique sur les deux plateformes.
  ///
  /// Il existait ici une variante Cupertino qui doublait celle-ci, et que iOS
  /// était seul à afficher. Elle ne référençait aucun jeton du design et
  /// codait ses couleurs en dur (`CupertinoColors`), donc restait hors charte
  /// pendant que la refonte avançait à côté. Repeindre le doublon n'aurait
  /// fait que reporter l'écart au prochain changement : il n'en reste qu'un,
  /// qui lit le thème. Les INTERACTIONS restent adaptatives (dialogues,
  /// indicateur d'activité).
  Widget _buildEcran(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  // Un formulaire ne se lit pas sur toute la largeur d'un
                  // ecran : au-dela, l'oeil perd la ligne entre le libelle et
                  // le champ. Sans effet sur un telephone, plus etroit que ca.
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Logo
                        SvgPicture.asset(
                          'assets/images/rempart-logo.svg',
                          width: 80,
                          height: 80,
                        ),
                        const SizedBox(height: 16),

                        // Titre
                        Text(
                          'Connexion',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),

                        Text(
                          'Connectez-vous à votre compte Rempart',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),

                        // Message d'erreur
                        if (_errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  color: theme.colorScheme.error,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: TextStyle(
                                      color: theme.colorScheme.onErrorContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Email
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            hintText: 'votre@email.com',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Veuillez entrer votre email';
                            }
                            if (!value.contains('@') || !value.contains('.')) {
                              return 'Veuillez entrer un email valide';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Mot de passe
                        TextFormField(
                          controller: _passwordController,
                          focusNode: _passwordFocus,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _handleLogin(),
                          decoration: InputDecoration(
                            labelText: 'Mot de passe',
                            prefixIcon: const Icon(Icons.lock_outlined),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Veuillez entrer votre mot de passe';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),

                        // Mot de passe oublié
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () =>
                                context.push('/mot-de-passe-oublie'),
                            child: const Text('Mot de passe oublié ?'),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Bouton connexion
                        LoadingButton(
                          onPressed: _handleLogin,
                          isLoading: _isLoading,
                          child: const Text('Se connecter'),
                        ),
                        const SizedBox(height: 8),

                        // Voir le commentaire cote Cupertino : meme entree, pour
                        // ne pas avoir a retaper son mot de passe partout.
                        TextButton.icon(
                          onPressed: () => context.go('/connexion-qr'),
                          icon: const Icon(Icons.qr_code_2),
                          label: const Text('Se connecter avec un code'),
                        ),
                        const SizedBox(height: 8),

                        // Divider
                        Row(
                          children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                'ou',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Lien inscription
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Pas encore de compte ?',
                              style: theme.textTheme.bodyMedium,
                            ),
                            TextButton(
                              onPressed: () => context.go('/register'),
                              child: const Text('Créer un compte'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_isLoading) const _VoileConnexion(),
        ],
      ),
    );
  }
}

/// Voile plein écran pendant la connexion.
///
/// La connexion enchaîne l'authentification Supabase puis l'ouverture de la
/// session Matrix : plusieurs secondes pendant lesquelles l'écran semblerait
/// figé sans ce retour visuel. Le voile absorbe aussi les appuis, pour éviter
/// une seconde tentative pendant que la première tourne.
class _VoileConnexion extends StatelessWidget {
  const _VoileConnexion();

  @override
  Widget build(BuildContext context) {
    final isIOS = estIOS;
    return AbsorbPointer(
      child: ColoredBox(
        color: const Color(0xB3000000),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isIOS)
                const CupertinoActivityIndicator(
                    radius: 18, color: Colors.white)
              else
                const SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              const SizedBox(height: 20),
              const Text(
                'Connexion en cours...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Ouverture de votre session sécurisée',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
