import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// La présentation de Rempart (`PresentationScreen`), montrée une fois par
/// compte, à la première ouverture de l'accueil.
///
/// Retenue dans les métadonnées du compte Supabase, et non sur l'appareil
/// seul : se connecter ensuite sur la version web ou un second téléphone ne
/// la remontre pas. Une copie locale, propre au compte, couvre le serveur
/// injoignable au moment de l'écrire.
abstract final class Presentation {
  static const _cle = 'presentation_vue';

  /// Vrai si ce compte l'a déjà vue, ici ou sur un autre appareil.
  static Future<bool> dejaVue() async {
    final compte = Supabase.instance.client.auth.currentUser;
    if (compte == null) return true;
    if (compte.userMetadata?[_cle] == true) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('${_cle}_${compte.id}') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> marquerVue() async {
    final auth = Supabase.instance.client.auth;
    final compte = auth.currentUser;
    if (compte == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('${_cle}_${compte.id}', true);
    } catch (_) {}
    try {
      // GoTrue fusionne : les autres métadonnées du compte restent.
      await auth.updateUser(UserAttributes(data: {_cle: true}));
    } catch (e) {
      debugPrint('Présentation : non retenue sur le compte ($e)');
    }
  }
}
