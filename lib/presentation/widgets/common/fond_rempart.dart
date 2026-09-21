import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import 'logo_rempart.dart';

/// Fond des écrans principaux : voile lumineux et logo semé en ombre.
///
/// Un aplat uni derrière des bulles blanches donne une impression de tableur.
/// Ici le fond porte l'identité : le logo de Rempart en ombre, répété avec
/// quelques créneaux et points pour aérer. Il se devine, il ne se lit pas.
///
/// Dessiné plutôt qu'image : le motif suit la couleur du thème (clair comme
/// sombre), reste net à toutes les densités et ne pèse rien dans l'APK.
class FondRempart extends StatelessWidget {
  const FondRempart({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sombre = theme.brightness == Brightness.dark;
    final encre = sombre ? Colors.white : RempartTokens.texteClair;

    return DecoratedBox(
      // Voile : plus clair en haut, plus dense en bas. L'écran paraît éclairé
      // depuis la barre du haut, ce qui creuse la page.
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: sombre
              ? [const Color(0xFF101A2C), RempartTokens.fondSombre]
              : [Colors.white, RempartTokens.fondClair],
        ),
      ),
      child: CustomPaint(
        painter: _FiligraneRempart(
          // Le filigrane est plus dense que le semis : c'est lui qu'on doit
          // sentir, l'autre n'est qu'une texture.
          logo: encre.withValues(alpha: sombre ? 0.055 : 0.05),
          semis: encre.withValues(alpha: sombre ? 0.05 : 0.045),
        ),
        child: child,
      ),
    );
  }
}

/// Le logo de Rempart en grand, et son écusson semé en petit.
class _FiligraneRempart extends CustomPainter {
  const _FiligraneRempart({required this.logo, required this.semis});

  final Color logo;
  final Color semis;

  /// Côté d'une cellule du semis.
  static const _pas = 66.0;

  @override
  void paint(Canvas canvas, Size size) {
    _semer(canvas, size);
  }

  void _semer(Canvas canvas, Size size) {
    final plein = Paint()..color = semis;

    final colonnes = (size.width / _pas).ceil() + 1;
    final lignes = (size.height / _pas).ceil() + 1;

    for (var j = 0; j < lignes; j++) {
      for (var i = 0; i < colonnes; i++) {
        // Une ligne sur deux est décalée d'une demi-cellule : sans ce décalage
        // l'œil voit des colonnes bien alignées, donc une grille.
        final centre = Offset(
          i * _pas + (j.isEven ? 0 : _pas / 2),
          j * _pas,
        );
        // Rotation légère, dérivée de la position : le motif paraît semé à la
        // main plutôt qu'estampillé.
        final angle = ((i * 7 + j * 13) % 12 - 6) * math.pi / 90;

        canvas
          ..save()
          ..translate(centre.dx, centre.dy)
          ..rotate(angle);
        switch ((i + j * 2) % 4) {
          // Le logo entier, écusson et « R » : c'est lui la signature du
          // fond. Les autres motifs ne sont là que pour aérer le semis, sans
          // quoi la répétition devient un papier peint bavard.
          case 0:
            _logoComplet(canvas, 38);
          case 1:
            canvas.drawCircle(Offset.zero, 2.2, plein);
          case 2:
            _logoComplet(canvas, 26);
          case 3:
            _creneaux(canvas, plein);
        }
        canvas.restore();
      }
    }
  }

  /// Le logo, en ombre : contour de l'écusson et « R » plein.
  void _logoComplet(Canvas canvas, double cote) {
    final contour = Paint()
      ..color = logo
      ..style = PaintingStyle.stroke
      ..strokeWidth = cote * 0.055
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawPath(TracesLogo.ecusson(Offset.zero, cote), contour)
      ..drawPath(
        TracesLogo.lettreR(Offset.zero, cote),
        Paint()..color = logo,
      );
  }

  /// Trois merlons : le rempart lui-même, réduit à sa dentelure.
  void _creneaux(Canvas canvas, Paint peinture) {
    for (var k = -1; k <= 1; k++) {
      canvas.drawRect(
        Rect.fromLTWH(k * 7 - 2.2, -4, 4.4, 8),
        peinture,
      );
    }
  }

  @override
  bool shouldRepaint(_FiligraneRempart ancien) =>
      ancien.logo != logo || ancien.semis != semis;
}
