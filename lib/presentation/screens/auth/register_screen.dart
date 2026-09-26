import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/plateforme.dart';
import '../../../core/utils/regles_mot_de_passe.dart';
import '../../../data/providers/providers.dart';
import '../../../services/auth_service.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/common/loading_button.dart';

/// Écran d'inscription
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _acceptTerms = false;
  String? _errorMessage;

  @override
  void dispose() {
    _displayNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_acceptTerms) {
      setState(() {
        _errorMessage = "Veuillez accepter les conditions d'utilisation";
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = ref.read(authServiceProvider);
      final response = await authService.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        displayName: _displayNameController.text.trim(),
      );

      if (mounted) {
        if (response.user != null && response.session != null) {
          // Inscription réussie avec session (email non requis)
          context.go('/home');
        } else {
          // Email de confirmation envoyé
          _showConfirmationDialog();
        }
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

  void _showConfirmationDialog() {
    if (estIOS) {
      showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Vérifiez votre email'),
          content: Text(
            'Un email de confirmation a été envoyé à ${_emailController.text}.\n\n'
            "Cliquez sur le lien dans l'email pour activer votre compte.",
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () {
                Navigator.of(context).pop();
                context.go('/login');
              },
              child: const Text('Compris'),
            ),
          ],
        ),
      );
    } else {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.mark_email_read_outlined, size: 48),
          title: const Text('Vérifiez votre email'),
          content: Text(
            'Un email de confirmation a été envoyé à ${_emailController.text}.\n\n'
            "Cliquez sur le lien dans l'email pour activer votre compte.",
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                context.go('/login');
              },
              child: const Text('Compris'),
            ),
          ],
        ),
      );
    }
  }

  String _getErrorMessage(dynamic error) {
    final message = error.toString().toLowerCase();
    debugPrint('Erreur inscription: $error');

    if (message.contains('user already registered')) {
      return 'Un compte existe déjà avec cet email';
    }
    if (message.contains('password') && !message.contains('email')) {
      return 'Le mot de passe ne respecte pas les critères';
    }
    if (message.contains('invalid') && message.contains('email')) {
      return "L'adresse email est invalide";
    }
    if (message.contains('network') || message.contains('connection')) {
      return 'Erreur de connexion. Vérifiez votre réseau.';
    }
    return 'Erreur: ${error.toString().length > 100 ? error.toString().substring(0, 100) : error.toString()}';
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Veuillez entrer un mot de passe';
    }
    return problemeMotDePasse(value);
  }

  @override
  Widget build(BuildContext context) {
    // L'etat vient du serveur, jamais d'une constante compilee : rouvrir les
    // inscriptions ne doit demander ni build, ni passage par les magasins.
    // Tant que la reponse n'est pas la, on montre le formulaire : un ecran
    // d'attente sur un chemin aussi court se lit comme une panne.
    final ouverte = ref.watch(inscriptionOuverteProvider).value ?? true;
    return ouverte ? _buildEcran(context) : _buildFerme(context);
  }

  /// Ce que voit quelqu'un quand les inscriptions sont fermees.
  ///
  /// Un formulaire qui refuse en 422 laisserait croire a une erreur de saisie.
  /// On dit donc ce qui se passe, pourquoi, et ce qu'il peut faire : ecrire
  /// pour etre prevenu. La connexion reste accessible, les comptes existants
  /// n'etant pas concernes.
  Widget _buildFerme(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(iconeRetour),
          onPressed: () => context.go('/login'),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SvgPicture.asset(
                    'assets/images/rempart-logo.svg',
                    width: 64,
                    height: 64,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Inscription bientôt disponible',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Rempart n'est pas encore ouvert au public. Les comptes "
                    'existants fonctionnent normalement, mais la création de '
                    'nouveaux comptes attend la vérification des adresses '
                    'électroniques.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: () => context.go('/login'),
                    child: const Text('Se connecter'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(iconeRetour),
          onPressed: () => context.go('/login'),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              // Meme raison qu'a la connexion : un formulaire etire sur
              // 1800 pixels devient illisible.
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
                      width: 64,
                      height: 64,
                    ),
                    const SizedBox(height: 16),

                    // Titre
                    Text(
                      'Créer un compte',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),

                    Text(
                      'Rejoignez la messagerie souveraine',
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

                    // Nom d'affichage
                    TextFormField(
                      controller: _displayNameController,
                      textInputAction: TextInputAction.next,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: "Nom d'affichage",
                        hintText: 'Comment voulez-vous être appelé ?',
                        prefixIcon: Icon(Icons.person_outlined),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Veuillez entrer votre nom';
                        }
                        if (value.length > AppConstants.maxDisplayNameLength) {
                          return 'Le nom est trop long';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

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
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Mot de passe',
                        helperText: consigneMotDePasse,
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
                      validator: _validatePassword,
                    ),
                    const SizedBox(height: 16),

                    // Confirmation mot de passe
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirmPassword,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _handleRegister(),
                      decoration: InputDecoration(
                        labelText: 'Confirmer le mot de passe',
                        prefixIcon: const Icon(Icons.lock_outlined),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureConfirmPassword =
                                  !_obscureConfirmPassword;
                            });
                          },
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Veuillez confirmer votre mot de passe';
                        }
                        if (value != _passwordController.text) {
                          return 'Les mots de passe ne correspondent pas';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    // Acceptation CGU
                    CheckboxListTile.adaptive(
                      value: _acceptTerms,
                      onChanged: (value) {
                        setState(() {
                          _acceptTerms = value ?? false;
                          if (_acceptTerms) {
                            _errorMessage = null;
                          }
                        });
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      title: RichText(
                        text: TextSpan(
                          style: theme.textTheme.bodyMedium,
                          children: [
                            const TextSpan(text: "J'accepte les "),
                            TextSpan(
                              text: "conditions d'utilisation",
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const TextSpan(text: ' et la '),
                            TextSpan(
                              text: 'politique de confidentialité',
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Bouton inscription
                    LoadingButton(
                      onPressed: _handleRegister,
                      isLoading: _isLoading,
                      child: const Text('Créer mon compte'),
                    ),
                    const SizedBox(height: 16),

                    // Lien connexion
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Déjà un compte ?',
                          style: theme.textTheme.bodyMedium,
                        ),
                        TextButton(
                          onPressed: () => context.go('/login'),
                          child: const Text('Se connecter'),
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
    );
  }
}
