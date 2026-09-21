import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../data/services/appairage_service.dart';

/// Se connecter en montrant un code à un appareil déjà connecté.
///
/// Le code n'est **pas** un mot de passe déguisé : il ne vaut que deux
/// minutes, ne sert qu'une fois, et ne donne rien tant que l'autre appareil
/// n'a pas confirmé. Il reste néanmoins un sésame le temps qu'il est affiché,
/// d'où l'avertissement à l'écran : on ne le montre pas à la cantonade.
class ConnexionQrScreen extends StatefulWidget {
  const ConnexionQrScreen({super.key});

  @override
  State<ConnexionQrScreen> createState() => _ConnexionQrScreenState();
}

class _ConnexionQrScreenState extends State<ConnexionQrScreen> {
  final _service = AppairageService();
  Appairage? _appairage;
  String? _erreur;
  bool _expire = false;

  @override
  void initState() {
    super.initState();
    unawaited(_demarrer());
  }

  Future<void> _demarrer() async {
    setState(() {
      _erreur = null;
      _expire = false;
      _appairage = null;
    });
    try {
      final appairage = await _service.demarrer();
      if (!mounted) return;
      setState(() => _appairage = appairage);

      final ouvert = await _service.attendrePuisOuvrirSession(appairage);
      if (!mounted) return;
      if (ouvert) {
        // La redirection du routeur suit la session Supabase : une fois
        // ouverte, l'accueil est atteignable.
        context.go('/home');
        return;
      }
      setState(() => _expire = true);
    } catch (e) {
      if (mounted) setState(() => _erreur = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Se connecter avec un code')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Sur un appareil où vous êtes déjà connecté, ouvrez '
                  '« Appareils connectés » puis « Connecter un appareil », et '
                  'visez ce code.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                if (_erreur != null)
                  _Message(
                    icone: Icons.cloud_off,
                    titre: 'Connexion impossible',
                    detail: _erreur!,
                    action: _demarrer,
                  )
                else if (_expire)
                  _Message(
                    icone: Icons.timer_off,
                    titre: 'Code expiré',
                    detail: 'Un code ne vaut que deux minutes, le temps de '
                        'prendre son autre appareil.',
                    action: _demarrer,
                  )
                else if (_appairage == null)
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(),
                  )
                else ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    // Fond clair imposé : un lecteur attend du sombre sur du
                    // clair, et un thème sombre rendrait le code illisible.
                    color: Colors.white,
                    child: QrImageView(
                      data: AppairageService.contenuQr(_appairage!),
                      size: 240,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        "En attente de l'autre appareil...",
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Ce code ouvre une session sur votre compte : ne le '
                    "montrez à personne, et ne le laissez pas à l'écran.",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Utiliser mon mot de passe'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icone,
    required this.titre,
    required this.detail,
    required this.action,
  });

  final IconData icone;
  final String titre;
  final String detail;
  final VoidCallback action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(icone, size: 40, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: 12),
        Text(titre, style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(detail, textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
        FilledButton(onPressed: action, child: const Text('Réessayer')),
      ],
    );
  }
}
