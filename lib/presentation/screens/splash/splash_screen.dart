
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/amorcage.dart';
import '../../../app/theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/plateforme.dart';

/// Écran de démarrage avec logo animé
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.5, curve: Curves.easeIn),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.5, curve: Curves.easeOut),
      ),
    );

    // `initState` ne peut pas lire `MediaQuery` : on interroge la plateforme
    // directement, qui est ce qu'il reflète.
    if (WidgetsBinding
        .instance.platformDispatcher.accessibilityFeatures.disableAnimations) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
    _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate() async {
    // On attend l'amorçage réel des services, pas un minuteur : c'est lui qui
    // détermine le moment où l'application est utilisable. Le délai ne sert
    // plus qu'à éviter que le logo n'apparaisse et ne disparaisse aussitôt
    // quand tout est déjà prêt.
    await Future.wait([
      Amorcage.futur,
      Future<void>.delayed(AppConstants.splashDuration),
    ]);

    if (!mounted) return;

    // Vérifier si l'utilisateur est connecté
    final session = Supabase.instance.client.auth.currentSession;

    if (session != null) {
      context.go('/home');
    } else {
      context.go('/login');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Le splash screen est identique sur iOS et Android (pas de navigation bar)
    // On utilise juste le bon indicateur de chargement
    final content = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          // Le bleu marine de l'icône, et non le bleu de Material : c'est la
          // couleur qu'on vient de toucher sur l'écran d'accueil, la même dans
          // les deux thèmes, comme l'icône elle-même.
          colors: const [RempartTokens.marine, RempartTokens.fondSombre],
        ),
      ),
      child: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Opacity(
              opacity: _fadeAnimation.value,
              child: Transform.scale(
                scale: _scaleAnimation.value,
                child: child,
              ),
            );
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(16),
                child: SvgPicture.asset(
                  'assets/images/rempart-logo.svg',
                ),
              ),

              const SizedBox(height: 32),

              // Nom
              const Text(
                'Rempart',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),

              const SizedBox(height: 8),

              // Tagline
              Text(
                'Messagerie souveraine',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white.withValues(alpha: 0.9),
                  letterSpacing: 0.5,
                ),
              ),

              const SizedBox(height: 48),

              // Indicateur de chargement adaptatif
              SizedBox(
                width: 24,
                height: 24,
                child: estIOS
                    ? const CupertinoActivityIndicator(
                        color: Colors.white,
                      )
                    : CircularProgressIndicator.adaptive(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );

    // Utiliser le bon conteneur selon la plateforme
    if (estIOS) {
      return CupertinoPageScaffold(
        child: content,
      );
    }

    return Scaffold(
      body: content,
    );
  }
}
