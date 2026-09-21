import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/plateforme.dart';
import '../data/providers/mode_theme.dart';
import '../data/services/matrix_service.dart';
import '../data/services/notification_service.dart';
import '../presentation/widgets/settings/verification_appareil.dart';
import 'cupertino_theme.dart';
import 'router.dart';
import 'theme.dart';

/// Application principale Rempart
/// Utilise CupertinoApp sur iOS et MaterialApp sur Android
class RempartApp extends ConsumerWidget {
  const RempartApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    // Toucher une notification ouvre la conversation concernée. Le service ne
    // connaît pas le routeur : on lui passe l'action ici.
    //
    // L'accueil est posé SOUS la conversation, sinon elle serait seule dans la
    // pile : le geste de retour fermait alors l'application, alors qu'on
    // attend d'arriver sur la liste des messages.
    NotificationService.instance.onOuvrirRoom = (roomId) {
      router
        ..go('/home')
        ..push('/chat/$roomId');
    };

    // Utiliser CupertinoApp sur iOS pour un rendu natif
    if (estIOS) {
      return _CupertinoAppWrapper(router: router);
    }

    // MaterialApp pour Android et autres plateformes
    return MaterialApp.router(
      title: 'Rempart',
      debugShowCheckedModeBanner: false,

      // Thème Material
      theme: RempartTheme.light,
      darkTheme: RempartTheme.dark,
      themeMode: ref.watch(modeThemeProvider),

      // Navigation
      routerConfig: router,

      // Une demande de vérification arrive quand l'AUTRE appareil la lance,
      // pas quand on ouvre l'écran des appareils : l'écoute doit donc vivre
      // au-dessus de la navigation, sur tous les écrans.
      builder: (context, child) => EcouteVerifications(
        demandes: MatrixService.instance.demandesDeVerification,
        enfant: child ?? const SizedBox.shrink(),
      ),

      // Localisation
      locale: const Locale('fr', 'FR'),
    );
  }
}

/// Wrapper pour CupertinoApp qui écoute les changements de thème système
class _CupertinoAppWrapper extends ConsumerStatefulWidget {
  const _CupertinoAppWrapper({required this.router});

  final RouterConfig<Object> router;

  @override
  ConsumerState<_CupertinoAppWrapper> createState() =>
      _CupertinoAppWrapperState();
}

class _CupertinoAppWrapperState extends ConsumerState<_CupertinoAppWrapper>
    with WidgetsBindingObserver {
  Brightness _brightness = PlatformDispatcher.instance.platformBrightness;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    setState(() {
      _brightness = PlatformDispatcher.instance.platformBrightness;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Le choix de l'utilisateur prime, la luminosité système ne sert que pour
    // « Système ». Sans cela, l'entrée « Apparence » du menu s'ouvrait,
    // enregistrait le choix... et ne changeait rien à l'écran sur iOS, seul
    // Android lisant `modeThemeProvider`.
    final isDark = switch (ref.watch(modeThemeProvider)) {
      ThemeMode.light => false,
      ThemeMode.dark => true,
      ThemeMode.system => _brightness == Brightness.dark,
    };

    return CupertinoApp.router(
      title: 'Rempart',
      debugShowCheckedModeBanner: false,

      // Thème Cupertino selon la luminosité système
      theme: isDark ? RempartCupertinoTheme.dark : RempartCupertinoTheme.light,

      // Navigation
      routerConfig: widget.router,

      // Localisation
      locale: const Locale('fr', 'FR'),

      // Permettre l'utilisation de Material widgets dans Cupertino
      localizationsDelegates: const [
        DefaultMaterialLocalizations.delegate,
        DefaultCupertinoLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],

      // Builder pour injecter le thème Material à l'intérieur de l'app
      // afin que les widgets Material fonctionnent correctement
      builder: (context, child) {
        return Theme(
          data: isDark ? RempartTheme.dark : RempartTheme.light,
          // `CupertinoApp` n'en pose aucun, la ou `MaterialApp` en pose un
          // d'office. Sans lui, tout `ScaffoldMessenger.of(context)` echoue sur
          // iOS - et les ecrans recents (appareils, mes bots, boutique,
          // profil, mot de passe...) signalent tous leurs succes et leurs
          // erreurs par un `SnackBar`.
          child: ScaffoldMessenger(
            child: EcouteVerifications(
              demandes: MatrixService.instance.demandesDeVerification,
              enfant: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }
}
