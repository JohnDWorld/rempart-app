
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../../core/plateforme.dart';

/// Repli quand aucun distributeur UnifiedPush n'est installé : un service de
/// premier plan empêche Android de tuer le processus, ce qui laisse vivre la
/// connexion Matrix de l'app et donc ses notifications.
///
/// Portée exacte, à ne pas surestimer : cela couvre l'app **en arrière-plan**
/// (autre application au premier plan, écran éteint). Si l'utilisateur balaie
/// Rempart hors des applications récentes, Android détruit le moteur Flutter
/// qui porte la synchronisation, et seul UnifiedPush prend alors le relais.
/// C'est pourquoi les deux mécanismes coexistent.
///
/// La tâche exécutée par le service ne fait volontairement rien : son seul rôle
/// est de maintenir le processus en vie. Y faire tourner une seconde
/// synchronisation Matrix reviendrait à ouvrir la base locale depuis deux
/// isolates, avec le risque de corruption que cela suppose.
class SyncArrierePlanService {
  SyncArrierePlanService._();

  static final SyncArrierePlanService instance = SyncArrierePlanService._();

  bool _configure = false;

  /// Notification permanente du service : discrète (importance basse) pour ne
  /// pas parasiter la liste des notifications.
  void _configurer() {
    if (_configure) return;
    _configure = true;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'rempart_sync',
        channelName: 'Connexion Rempart',
        channelDescription:
            'Maintient la réception des messages quand Rempart est en arrière-plan.',
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        // Aucun travail périodique : le service sert uniquement à garder le
        // processus vivant.
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWifiLock: true,
      ),
    );
  }

  /// Démarre le repli. Sans effet hors Android : iOS interdit ce genre de
  /// service, la plateforme y impose son propre push.
  Future<void> demarrer() async {
    if (!estAndroid) return;
    _configurer();

    if (await FlutterForegroundTask.isRunningService) return;

    final resultat = await FlutterForegroundTask.startService(
      notificationTitle: 'Rempart',
      notificationText: 'Réception des messages active',
    );
    if (resultat is ServiceRequestFailure) {
      debugPrint('Sync: service de premier plan refusé (${resultat.error})');
    }
  }

  /// Arrête le repli : plus nécessaire dès qu'UnifiedPush prend le relais, ou
  /// à la déconnexion.
  Future<void> arreter() async {
    if (!estAndroid) return;
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.stopService();
  }
}
