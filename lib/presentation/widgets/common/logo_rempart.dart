import 'package:flutter/material.dart';

/// Le logo de Rempart, dessiné : écusson hexagonal et « R » créneau.
///
/// Dessiné et non chargé du SVG : il sert de motif de fond (répété des
/// dizaines de fois par image) autant que de marque dans la barre du haut, et
/// un `Path` prêt à l'emploi évite de traverser le décodeur à chaque trame.
class LogoRempart extends StatelessWidget {
  const LogoRempart({required this.taille, this.couleur, super.key});

  final double taille;

  /// Couleur unique. À défaut, les couleurs de la marque : écusson ardoise (ou
  /// clair en thème sombre) et « R » doré.
  final Color? couleur;

  @override
  Widget build(BuildContext context) {
    final sombre = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: taille,
      height: taille,
      child: CustomPaint(
        painter: _PeintreLogo(
          ecusson: couleur ??
              (sombre ? const Color(0xFFE8EDF5) : const Color(0xFF2D3E50)),
          lettre: couleur ?? const Color(0xFFC9922B),
        ),
      ),
    );
  }
}

class _PeintreLogo extends CustomPainter {
  const _PeintreLogo({required this.ecusson, required this.lettre});

  final Color ecusson;
  final Color lettre;

  @override
  void paint(Canvas canvas, Size size) {
    final cote = size.shortestSide;
    final centre = Offset(size.width / 2, size.height / 2);
    canvas
      ..drawPath(
        TracesLogo.ecusson(centre, cote),
        Paint()
          ..color = ecusson
          ..style = PaintingStyle.stroke
          ..strokeWidth = cote * 0.055
          ..strokeJoin = StrokeJoin.round,
      )
      ..drawPath(
        TracesLogo.lettreR(centre, cote),
        Paint()..color = lettre,
      );
  }

  @override
  bool shouldRepaint(_PeintreLogo ancien) =>
      ancien.ecusson != ecusson || ancien.lettre != lettre;
}

/// Marque « Rempart » : le logo tient lieu de R, le mot suit.
class MarqueRempart extends StatelessWidget {
  const MarqueRempart({
    this.taille = 38,
    this.avecSousTitre = false,
    super.key,
  });

  final double taille;

  /// Ajoute « Messagerie souveraine » sous le mot.
  ///
  /// Réservé aux en-têtes qui ont la place de deux lignes : sur un téléphone,
  /// la barre du haut est déjà pleine, et la promesse y volerait la place du
  /// nom.
  final bool avecSousTitre;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final marque = _marque(theme);
    if (!avecSousTitre) return marque;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        marque,
        const SizedBox(height: 2),
        Text(
          'Messagerie souveraine',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }

  Widget _marque(ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      // Le mot prolonge le « R » : même ligne de pied que lui, et non le bas
      // de l'écusson ni un centrage en hauteur, qui le faisaient flotter.
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        // Le logo n'a pas de ligne de pied : on lui déclare celle de sa
        // lettre (y = 367 sur 512 dans le SVG).
        Baseline(
          baseline: taille * 0.717,
          baselineType: TextBaseline.alphabetic,
          child: LogoRempart(taille: taille),
        ),
        // Chasse resserrée : le « e » touche presque l'écusson pour que l'œil
        // lise un seul mot. Un décalage négatif, car l'écusson porte déjà sa
        // propre marge intérieure, qui creuse l'écart.
        Transform.translate(
          offset: const Offset(-3, 0),
          child: Text(
            'empart',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              height: 1,
            ),
          ),
        ),
      ],
    );
  }
}

/// Tracés du logo, transcrits de `assets/images/rempart-logo.svg`.
///
/// Transcrits et non chargés depuis le SVG : le fond se redessine à chaque
/// image, et un `Path` prêt à l'emploi évite de traverser le décodeur à
/// chaque fois. Les coordonnées restent celles du fichier (repère 512), ce qui
/// permet de comparer les deux à l'œil en cas de retouche du logo.
abstract class TracesLogo {
  /// Hexagone aux coins arrondis, centré sur [centre] et inscrit dans [cote].
  static Path ecusson(Offset centre, double cote) {
    final chemin = Path()
      ..moveTo(256, 55)
      ..quadraticBezierTo(266, 55, 276, 61)
      ..lineTo(418, 152)
      ..quadraticBezierTo(432, 161, 432, 176)
      ..lineTo(432, 336)
      ..quadraticBezierTo(432, 351, 418, 360)
      ..lineTo(276, 451)
      ..quadraticBezierTo(266, 457, 256, 457)
      ..quadraticBezierTo(246, 457, 236, 451)
      ..lineTo(94, 360)
      ..quadraticBezierTo(80, 351, 80, 336)
      ..lineTo(80, 176)
      ..quadraticBezierTo(80, 161, 94, 152)
      ..lineTo(236, 61)
      ..quadraticBezierTo(246, 55, 256, 55)
      ..close();
    return _ajuster(chemin, centre, cote);
  }

  /// Le « R », dont le bord gauche est crénelé.
  ///
  /// Le créneau, le merlon et les marges partagent la MÊME unité : c'est ce qui
  /// fait lire un rempart plutôt qu'une crémaillère. La jambe va de 145 à 367,
  /// soit 222, d'où la règle qui donne tout le reste :
  ///
  ///     222 = (2 × nombre de créneaux + 1) × unité
  ///
  /// Trois créneaux donnent donc une unité de 32, et une profondeur de 15 sur
  /// une jambe large de 42. Changer le nombre sans rejouer cette règle casse le
  /// motif : en passant de quatre à trois sans réespacer, les merlons ont
  /// doublé de hauteur et le dessin est devenu une barre à trois entailles.
  ///
  /// Les mêmes valeurs vivent dans les cinq SVG et dans la page publique. Les
  /// désaccorder donnerait deux logos selon l'écran, et cela ne se verrait que
  /// par hasard.
  static const _creneaux = [176.0, 240.0, 304.0];
  static const _unite = 32.0;
  static const _profondeur = 15.0;

  static Path lettreR(Offset centre, double cote) {
    final lettre = Path()..moveTo(185, 145);

    // Les créneaux font partie du CONTOUR, ils ne sont pas soustraits après
    // coup. Soustraits, leur bord gauche tombait exactement sur celui du R :
    // deux contours superposés que le rendu lisse séparément, laissant un
    // liseré doré à 17 % d'opacité qui refermait les encoches. Mesuré, pas
    // supposé. Un seul tracé n'a rien à annuler.
    for (final y in _creneaux) {
      lettre
        ..lineTo(185, y)
        ..lineTo(185 + _profondeur, y)
        ..lineTo(185 + _profondeur, y + _unite)
        ..lineTo(185, y + _unite);
    }

    lettre
      ..lineTo(185, 367)
      ..lineTo(227, 367)
      ..lineTo(227, 285)
      ..lineTo(285, 367)
      ..lineTo(340, 367)
      ..lineTo(275, 278)
      ..quadraticBezierTo(342, 265, 342, 218)
      ..quadraticBezierTo(342, 170, 300, 152)
      ..quadraticBezierTo(285, 145, 260, 145)
      ..close()
      // Contre-forme de la boucle du R.
      ..moveTo(227, 185)
      ..lineTo(260, 185)
      ..quadraticBezierTo(285, 185, 295, 195)
      ..quadraticBezierTo(305, 205, 305, 218)
      ..quadraticBezierTo(305, 235, 295, 243)
      ..quadraticBezierTo(285, 252, 260, 252)
      ..lineTo(227, 252)
      ..close()
      ..fillType = PathFillType.evenOdd;

    return _ajuster(lettre, centre, cote);
  }

  /// Met un tracé du repère 512 à l'échelle voulue, centré sur [centre].
  static Path _ajuster(Path chemin, Offset centre, double cote) {
    final facteur = cote / 512;
    final matrice = Matrix4.identity()
      ..translateByDouble(
        centre.dx - cote / 2,
        centre.dy - cote / 2,
        0,
        1,
      )
      ..scaleByDouble(facteur, facteur, 1, 1);
    return chemin.transform(matrice.storage);
  }
}
