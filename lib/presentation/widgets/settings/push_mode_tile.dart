import 'package:flutter/material.dart';

import '../../../core/constants/push_constants.dart';
import '../../../data/services/push_service.dart';
import '../../../data/services/sync_arriere_plan_service.dart';

/// Réglage du mécanisme de notification, avec son état réel.
///
/// Le choix engage la confidentialité (Google dans la chaîne ou non), il est
/// donc explicite plutôt que caché dans un build : l'utilisateur voit ce qui
/// s'applique vraiment, y compris quand sa préférence n'a pas pu être honorée
/// (Play Services absent, aucun distributeur installé).
class PushModeTile extends StatefulWidget {
  const PushModeTile({super.key});

  @override
  State<PushModeTile> createState() => _PushModeTileState();
}

class _PushModeTileState extends State<PushModeTile> {
  ModePush? _mode;
  bool _enCours = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final mode = await PushService.instance.modeActif();
    if (mounted) {
      setState(() => _mode = mode);
    }
  }

  /// Ce qui fonctionne réellement, qui peut différer du mode demandé.
  String get _etatReel {
    switch (PushService.instance.transport) {
      case TransportPush.fcm:
        return 'Actif via Google';
      case TransportPush.unifiedpush:
        return 'Actif via UnifiedPush';
      case TransportPush.aucun:
        return "Aucun push : l'app doit rester en arrière-plan";
      case TransportPush.refuse:
        return 'Notifications bloquées dans les réglages du téléphone';
    }
  }

  Future<void> _choisir() async {
    final choix = await showDialog<ModePush>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Notifications'),
        children: [
          for (final mode in ModePush.values)
            ListTile(
              leading: Icon(
                mode == _mode
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(mode.libelle),
              subtitle: Text(mode.description),
              isThreeLine: true,
              onTap: () => Navigator.pop(context, mode),
            ),
          if (!PushConstants.fcmDisponible)
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Text(
                'Cette version ne contient pas la configuration Google : '
                'le mode « Google (FCM) » restera sans effet.',
                style: TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    );
    if (choix == null || !mounted) return;

    setState(() => _enCours = true);
    final transport = await PushService.instance.choisirMode(choix);
    // Sans push, l'app se rabat sur sa propre connexion maintenue en vie.
    if (transport == TransportPush.aucun) {
      await SyncArrierePlanService.instance.demarrer();
    } else {
      await SyncArrierePlanService.instance.arreter();
    }
    if (mounted) {
      setState(() {
        _mode = choix;
        _enCours = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = _mode;
    return ListTile(
      leading: const Icon(Icons.notifications_outlined),
      title: const Text('Notifications push'),
      subtitle: Text(
        mode == null ? '...' : '${mode.libelle} · $_etatReel',
      ),
      trailing: _enCours
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right),
      onTap: _enCours ? null : _choisir,
    );
  }
}
