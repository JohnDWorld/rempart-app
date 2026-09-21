import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/plateforme.dart';

/// Android endort-il Rempart au point de retarder ses notifications ?
///
/// C'est la cause la plus fréquente d'un message qui n'arrive qu'à l'ouverture
/// de l'application, alors que le serveur l'a bien poussé. Android met en
/// veille les applications qu'il juge inutilisées, et les surcouches
/// constructeur, Samsung en tête, plus tôt encore : le message pousse attend
/// alors le réveil, c'est-à-dire le moment où l'on ouvre Rempart, ce qui vide
/// la notification de tout intérêt.
///
/// Rien ne se règle sans l'utilisateur : seul lui peut lever la bride, depuis
/// les réglages du téléphone.
class VeilleBatterie {
  VeilleBatterie._();

  static const _canal = MethodChannel('rempart/maj');

  /// Vrai si Android peut retarder nos notifications.
  ///
  /// Faux hors Android, et faux en cas de doute : mieux vaut se taire qu'agiter
  /// un avertissement là où il n'y a rien à corriger.
  static Future<bool> bridee() async {
    if (!estAndroid) return false;
    try {
      return await _canal.invokeMethod<bool>('batterieBridee') ?? false;
    } catch (e) {
      debugPrint('[batterie] état inconnu : $e');
      return false;
    }
  }

  /// Ouvre la liste système « Optimisation de la batterie ».
  ///
  /// La liste, et non la demande directe : celle-ci exige une permission que
  /// le Play Store n'accorde qu'au cas par cas.
  static Future<void> ouvrirReglages() =>
      _canal.invokeMethod<void>('ouvrirReglageBatterie');
}
