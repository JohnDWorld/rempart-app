import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../data/services/enregistrement_photos.dart';

/// Interrupteur « Enregistrer les photos reçues » (album Rempart de la
/// galerie), dans ses deux habits : ligne Material, ou ligne d'une section
/// iOS.
class EnregistrementPhotosTile extends StatefulWidget {
  const EnregistrementPhotosTile({this.cupertino = false, super.key});

  final bool cupertino;

  @override
  State<EnregistrementPhotosTile> createState() =>
      _EnregistrementPhotosTileState();
}

class _EnregistrementPhotosTileState extends State<EnregistrementPhotosTile> {
  bool _actif = EnregistrementPhotos.instance.actif;
  bool _enCours = false;

  static const _titre = 'Enregistrer les photos reçues';

  /// L'avertissement fait partie du réglage : une photo enregistrée sort du
  /// chiffrement, et c'est ce que l'on accepte en l'activant.
  static const _description =
      "Dans l'album Rempart de la galerie. Elles y sortent du chiffrement : "
      'les autres applications et la sauvegarde de la galerie y ont accès.';

  @override
  void initState() {
    super.initState();
    EnregistrementPhotos.instance.charger().then((_) {
      if (mounted) setState(() => _actif = EnregistrementPhotos.instance.actif);
    });
  }

  Future<void> _basculer(bool valeur) async {
    setState(() => _enCours = true);
    final service = EnregistrementPhotos.instance;
    var refuse = false;
    if (valeur) {
      refuse = !await service.activer();
    } else {
      await service.desactiver();
    }
    if (!mounted) return;
    setState(() {
      _actif = service.actif;
      _enCours = false;
    });
    if (refuse) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Accès à la galerie refusé : autorisez-le dans les réglages du '
            'téléphone.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final onChanged = _enCours ? null : _basculer;
    if (widget.cupertino) {
      return CupertinoListTile.notched(
        leading: const Icon(CupertinoIcons.photo_on_rectangle),
        title: const Text(_titre),
        subtitle: const Text(_description, maxLines: 3),
        trailing: CupertinoSwitch(value: _actif, onChanged: onChanged),
      );
    }
    return SwitchListTile(
      secondary: const Icon(Icons.photo_library_outlined),
      title: const Text(_titre),
      subtitle: const Text(_description),
      value: _actif,
      onChanged: onChanged,
    );
  }
}
