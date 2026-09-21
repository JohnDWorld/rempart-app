import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/services/veille_batterie.dart';

/// Avertit quand Android peut retarder les notifications de Rempart.
///
/// N'apparaît **que** si la bride est réellement active : un avertissement
/// permanent finit par ne plus être lu, et il n'y aurait alors rien à faire de
/// celui-ci le jour où il compte.
class VeilleBatterieTile extends StatefulWidget {
  const VeilleBatterieTile({super.key});

  @override
  State<VeilleBatterieTile> createState() => _VeilleBatterieTileState();
}

class _VeilleBatterieTileState extends State<VeilleBatterieTile>
    with WidgetsBindingObserver {
  bool _bridee = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_verifier());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Au retour des réglages système : l'avertissement doit disparaître sans
    // qu'on ait à ressortir de l'écran pour constater que c'est réglé.
    if (state == AppLifecycleState.resumed) unawaited(_verifier());
  }

  Future<void> _verifier() async {
    final bridee = await VeilleBatterie.bridee();
    if (mounted && bridee != _bridee) setState(() => _bridee = bridee);
  }

  @override
  Widget build(BuildContext context) {
    if (!_bridee) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return ListTile(
      leading: Icon(Icons.battery_alert_outlined, color: theme.colorScheme.error),
      title: const Text('Notifications retardées'),
      subtitle: const Text(
        'Android met Rempart en veille : les messages peuvent n’arriver '
        "qu'à l'ouverture de l'application. Touchez pour l'autoriser à rester "
        'joignable.',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        try {
          await VeilleBatterie.ouvrirReglages();
        } catch (e) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Réglages inaccessibles : $e')),
          );
        }
      },
    );
  }
}
