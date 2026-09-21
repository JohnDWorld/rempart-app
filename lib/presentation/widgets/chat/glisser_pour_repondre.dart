import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/mouvement.dart';

/// Glisser un message vers la droite pour y répondre.
///
/// Le geste de WhatsApp et de Telegram : plus direct que l'appui long suivi
/// d'un menu, qui reste disponible pour tout le reste (copier, réagir,
/// supprimer). Toujours vers la droite, quel que soit l'expéditeur, pour que
/// le geste ne dépende pas du côté où la bulle se trouve.
class GlisserPourRepondre extends StatefulWidget {
  const GlisserPourRepondre({
    required this.onRepondre,
    required this.child,
    super.key,
  });

  final VoidCallback onRepondre;
  final Widget child;

  @override
  State<GlisserPourRepondre> createState() => _GlisserPourRepondreState();
}

class _GlisserPourRepondreState extends State<GlisserPourRepondre> {
  /// Distance au-delà de laquelle le doigt relâché déclenche la réponse.
  static const _seuil = 56.0;

  double _decalage = 0;
  bool _glisse = false;
  bool _franchi = false;

  void _majDecalage(DragUpdateDetails d) {
    setState(() {
      _glisse = true;
      // Au-delà du seuil, le message résiste : le geste reste lisible sans
      // que la bulle parte à l'autre bout de l'écran.
      final pas = _decalage >= _seuil ? d.delta.dx / 3 : d.delta.dx;
      _decalage = (_decalage + pas).clamp(0.0, _seuil + 24);
    });
    if (_decalage >= _seuil && !_franchi) {
      _franchi = true;
      // La vibration dit que lâcher maintenant répondra : sans elle, il faut
      // regarder la flèche, donc quitter des yeux ce qu'on lit.
      HapticFeedback.lightImpact();
    } else if (_decalage < _seuil) {
      _franchi = false;
    }
  }

  void _relacher() {
    final repond = _decalage >= _seuil;
    setState(() {
      _glisse = false;
      _decalage = 0;
      _franchi = false;
    });
    if (repond) widget.onRepondre();
  }

  @override
  Widget build(BuildContext context) {
    final progression = (_decalage / _seuil).clamp(0.0, 1.0);
    return GestureDetector(
      // Seul l'horizontal est capté : le vertical reste au défilement du fil.
      onHorizontalDragUpdate: _majDecalage,
      onHorizontalDragEnd: (_) => _relacher(),
      onHorizontalDragCancel: _relacher,
      child: Stack(
        children: [
          // La flèche se dévoile derrière le message à mesure du glissement.
          Positioned.fill(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Opacity(
                  opacity: progression,
                  child: Transform.scale(
                    scale: 0.6 + 0.4 * progression,
                    child: Icon(
                      Icons.reply,
                      size: 22,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          AnimatedContainer(
            // Le doigt commande directement ; c'est le retour qui s'anime.
            duration: _glisse
                ? Duration.zero
                : dureeAnimation(context, const Duration(milliseconds: 180)),
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(_decalage, 0, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
