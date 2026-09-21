import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thème choisi par l'utilisateur : clair, sombre, ou celui du système.
///
/// La valeur est relue au démarrage et injectée par `main.dart` (voir
/// `chargerModeTheme`) : sans cela l'app s'ouvrirait toujours en « système »
/// le temps de la lecture, et le thème sauterait sous les yeux.
final modeThemeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

const _cle = 'mode_theme';

/// Lit le mode enregistré. `system` par défaut, y compris si rien n'est lisible.
Future<ThemeMode> chargerModeTheme() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return switch (prefs.getString(_cle)) {
      'clair' => ThemeMode.light,
      'sombre' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  } catch (_) {
    return ThemeMode.system;
  }
}

/// Enregistre le mode. Best-effort : un échec d'écriture ne doit pas empêcher
/// le changement de thème, déjà appliqué à l'écran.
Future<void> enregistrerModeTheme(ThemeMode mode) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cle,
      switch (mode) {
        ThemeMode.light => 'clair',
        ThemeMode.dark => 'sombre',
        ThemeMode.system => 'systeme',
      },
    );
  } catch (_) {
    // Sans persistance, le choix vaut pour la session : c'est déjà mieux
    // que de refuser le changement.
  }
}

/// Libellé affiché dans le menu.
String libelleModeTheme(ThemeMode mode) => switch (mode) {
      ThemeMode.light => 'Clair',
      ThemeMode.dark => 'Sombre',
      ThemeMode.system => 'Système',
    };
