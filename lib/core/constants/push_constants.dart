import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../plateforme.dart';

/// Mécanisme de notification retenu pour cette installation.
enum ModePush {
  /// FCM si configuré, sinon UnifiedPush, sinon repli local.
  auto,

  /// Grand public : Google FCM, comme WhatsApp ou Messenger.
  fcm,

  /// Souverain : UnifiedPush, aucun service Google dans la chaîne.
  unifiedpush,

  /// Aucun push : notifications seulement quand l'app vit.
  aucun;

  static ModePush depuis(String? valeur) {
    switch (valeur?.trim().toLowerCase()) {
      case 'fcm':
        return ModePush.fcm;
      case 'unifiedpush':
      case 'up':
        return ModePush.unifiedpush;
      case 'aucun':
      case 'none':
        return ModePush.aucun;
      default:
        return ModePush.auto;
    }
  }

  String get libelle => switch (this) {
        ModePush.auto => 'Automatique',
        ModePush.fcm => 'Google (FCM)',
        ModePush.unifiedpush => 'Souverain (UnifiedPush)',
        ModePush.aucun => 'Aucun',
      };

  String get description => switch (this) {
        ModePush.auto =>
          'Utilise Google si configuré, sinon la voie souveraine.',
        ModePush.fcm =>
          'Notifications instantanées et sobres en batterie, comme les autres '
              "messageries. Google voit qu'une notification vous est destinée, "
              'jamais son contenu.',
        ModePush.unifiedpush =>
          'Aucun service Google : tout passe par le serveur Rempart. Demande '
              'une application distributeur (ntfy) sur le téléphone.',
        ModePush.aucun => "Aucune notification quand l'application est fermée.",
      };
}

/// Configuration du push. Tout est pilotable depuis le `.env` : une même base
/// de code sert la variante grand public (FCM) et la variante souveraine
/// (UnifiedPush), sans recompilation conditionnelle.
abstract class PushConstants {
  /// Mécanisme par défaut de ce build. L'utilisateur peut le surcharger dans
  /// les réglages ; voir `PushService`.
  static ModePush get modeParDefaut => ModePush.depuis(dotenv.env['PUSH_MODE']);

  /// URL de la passerelle UnifiedPush, telle que **Synapse** doit la joindre.
  ///
  /// Contre-intuitif : cette adresse n'est jamais appelée par l'app. Elle est
  /// transmise au serveur lors de la déclaration du pusher, et c'est Synapse
  /// qui la contacte. Elle doit donc être résolvable depuis le serveur, d'où
  /// une adresse interne au réseau Docker et non une adresse publique.
  static String get gatewayUrl =>
      _lire('PUSH_GATEWAY_URL') ??
      'http://push-gateway:8500/_matrix/push/v1/notify';

  /// Passerelle FCM (Sygnal), également appelée par Synapse et non par l'app.
  static String get fcmGatewayUrl =>
      _lire('FCM_GATEWAY_URL') ?? 'http://sygnal:5000/_matrix/push/v1/notify';

  /// Identifiants Firebase, fournis directement plutôt que par un
  /// `google-services.json` : la variante souveraine reste ainsi constructible
  /// sans le moindre fichier Google, et basculer d'un projet Firebase à un
  /// autre ne demande qu'un `.env`.
  static FirebaseOptions? get optionsFirebase =>
      optionsFirebasePour(ios: estIOS, lire: _lire);

  /// Les identifiants Firebase de la plateforme [ios] ou Android.
  ///
  /// Une application Firebase a un identifiant **par plateforme**
  /// (`1:<projet>:android:<…>`, `1:<projet>:ios:<…>`), et sa clé d'API est
  /// en général restreinte à elle. L'iPhone lit donc les siens,
  /// `FCM_APP_ID_IOS` et `FCM_API_KEY_IOS`.
  ///
  /// Le garde-fou sur le format n'est pas de la prudence : un identifiant
  /// d'une autre plateforme fait lever à Firebase une exception Objective-C
  /// (`FIRApp configureWithName`), que le `try` de Dart ne voit jamais, et
  /// l'application se ferme. C'est ce qui arrivait sur iPhone avec le `.env`
  /// de production, qui ne porte que l'identifiant Android : plantage à
  /// chaque lancement (vu le 2026-10-27). Mieux vaut un iPhone sans
  /// notifications FCM qu'une application qui ne s'ouvre pas.
  @visibleForTesting
  static FirebaseOptions? optionsFirebasePour({
    required bool ios,
    required String? Function(String cle) lire,
  }) {
    final apiKey = lire(ios ? 'FCM_API_KEY_IOS' : 'FCM_API_KEY');
    final appId = lire(ios ? 'FCM_APP_ID_IOS' : 'FCM_APP_ID');
    final senderId = lire('FCM_SENDER_ID');
    final projectId = lire('FCM_PROJECT_ID');
    if (apiKey == null ||
        appId == null ||
        senderId == null ||
        projectId == null) {
      return null;
    }
    if (!appId.contains(ios ? ':ios:' : ':android:')) {
      debugPrint('Push: identifiant Firebase $appId refusé, il ne vise pas '
          '${ios ? 'iOS' : 'Android'}');
      return null;
    }
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: senderId,
      projectId: projectId,
    );
  }

  /// FCM utilisable dans ce build (identifiants Firebase renseignés).
  static bool get fcmDisponible => optionsFirebase != null;

  static String? _lire(String cle) {
    final valeur = dotenv.env[cle]?.trim();
    return (valeur == null || valeur.isEmpty) ? null : valeur;
  }
}
