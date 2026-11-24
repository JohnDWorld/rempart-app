import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/mouvement.dart';

/// Bulle du contact pendant qu'il écrit (trois points qui s'allument l'un
/// après l'autre) ou enregistre un vocal (un micro qui pulse lentement).
///
/// Elle a la forme d'une bulle reçue, à sa place : c'est là que le message va
/// arriver. Si le système demande moins de mouvement, points et micro restent
/// fixes, l'information demeure.
class IndicateurActivite extends StatefulWidget {
  const IndicateurActivite({
    required this.enregistre,
    required this.libelle,
    super.key,
  });

  /// Micro plutôt que points.
  final bool enregistre;

  /// Ce que lit un lecteur d'écran (« Léa écrit... »).
  final String libelle;

  @override
  State<IndicateurActivite> createState() => _IndicateurActiviteState();
}

class _IndicateurActiviteState extends State<IndicateurActivite>
    with SingleTickerProviderStateMixin {
  /// Un cycle : les trois points passent, ou le micro respire une fois.
  late final _cycle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (animationsReduites(context)) {
      _cycle.stop();
    } else if (!_cycle.isAnimating) {
      _cycle.repeat();
    }
  }

  @override
  void dispose() {
    _cycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final schema = theme.colorScheme;
    final fixe = animationsReduites(context);

    return Semantics(
      liveRegion: true,
      label: widget.libelle,
      excludeSemantics: true,
      child: Padding(
        // L'avatar des bulles reçues occupe 40 points à gauche.
        padding: const EdgeInsets.fromLTRB(
          RempartTokens.espaceS + 40,
          3,
          RempartTokens.espaceS,
          3,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: schema.surface,
              border: Border.all(color: schema.outlineVariant),
              boxShadow: RempartTokens.ombreLegere(theme.brightness),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(RempartTokens.rayonBulle),
                topRight: Radius.circular(RempartTokens.rayonBulle),
                bottomLeft: Radius.circular(6),
                bottomRight: Radius.circular(RempartTokens.rayonBulle),
              ),
            ),
            child: SizedBox(
              height: 20,
              child: AnimatedBuilder(
                animation: _cycle,
                builder: (context, _) => widget.enregistre
                    ? Opacity(
                        opacity: fixe ? 1 : _respiration(_cycle.value),
                        child: Icon(
                          Icons.mic_rounded,
                          size: 20,
                          color: schema.primary,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < 3; i++)
                            Padding(
                              padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
                              child: Opacity(
                                opacity:
                                    fixe ? 0.6 : _eclat(_cycle.value, rang: i),
                                child: Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: schema.onSurfaceVariant,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Opacité du micro : monte puis redescend une fois par cycle, sans à-coup.
  static double _respiration(double t) =>
      0.3 + 0.7 * (0.5 - 0.5 * math.cos(2 * math.pi * t));

  /// Opacité d'un point : chacun s'allume à son tour, avec un léger retard
  /// sur le précédent, puis s'éteint jusqu'au cycle suivant.
  static double _eclat(double t, {required int rang}) {
    final phase = (t - rang * 0.18) % 1;
    final eclat = phase < 0.5 ? math.sin(math.pi * phase / 0.5) : 0.0;
    return 0.3 + 0.7 * eclat;
  }
}
