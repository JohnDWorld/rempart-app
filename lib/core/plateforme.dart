import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Sommes-nous sur iOS ?
///
/// À préférer partout à `Platform.isIOS` : sur le web, `dart:io` n'existe pas
/// et toucher à `Platform` lève une `UnsupportedError`, ce qui casse l'écran
/// avant même qu'il ne s'affiche. Le `!kIsWeb` en tête court-circuite l'appel,
/// et le compilateur web supprime purement et simplement la branche, `kIsWeb`
/// étant une constante à la compilation.
bool get estIOS => !kIsWeb && Platform.isIOS;

/// Sommes-nous sur Android ? Voir [estIOS] pour le pourquoi du `!kIsWeb`.
bool get estAndroid => !kIsWeb && Platform.isAndroid;

/// Sommes-nous dans un navigateur ?
///
/// Réexporté ici pour que les écrans n'aient qu'un seul endroit où chercher,
/// et ne raisonnent jamais en « ni Android ni iOS donc web ».
bool get estWeb => kIsWeb;
