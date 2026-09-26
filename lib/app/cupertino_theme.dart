import 'package:flutter/cupertino.dart';

import 'theme.dart';

/// Thème Cupertino de Rempart, dérivé des mêmes jetons que le thème Material.
///
/// Il ne subsiste du monde Cupertino que le « chrome » : barres de navigation,
/// dialogues, feuilles d'actions. Le corps des écrans, lui, est dessiné une
/// seule fois (voir `ConversationsScreen`). Ce thème n'a donc qu'un travail :
/// que ce chrome parle la même langue que le reste.
///
/// Il vivait auparavant sa vie de son côté, avec son propre bleu et ses
/// propres gris : sur iOS, les barres restaient de l'ancienne identité pendant
/// que le corps portait la nouvelle. Tout part maintenant de
/// [RempartTokens], donc une retouche des jetons se propage aux deux mondes.
abstract class RempartCupertinoTheme {
  /// Accent : le bleu du design système, et non plus le bleu Material par
  /// défaut d'origine.
  static const Color primaryColor = RempartTokens.bleu;

  static CupertinoThemeData get light => _theme(Brightness.light);

  static CupertinoThemeData get dark => _theme(Brightness.dark);

  static CupertinoThemeData _theme(Brightness luminosite) {
    final sombre = luminosite == Brightness.dark;
    final texte = sombre ? RempartTokens.texteSombre : RempartTokens.texteClair;

    return CupertinoThemeData(
      brightness: luminosite,
      primaryColor: sombre ? RempartTokens.bleuClair : RempartTokens.bleu,
      // Le texte posé sur l'accent : celui du thème Material, pour une seule
      // source. Il était blanc dans les deux modes, or l'accent s'éclaircit
      // en sombre, et un bouton plein tombait alors à 2,5:1 de contraste (il
      // en faut 4,5). Le bleu très sombre de Material y tient 7,4:1.
      primaryContrastingColor:
          (sombre ? RempartTheme.dark : RempartTheme.light)
              .colorScheme
              .onPrimary,
      scaffoldBackgroundColor:
          sombre ? RempartTokens.fondSombre : RempartTokens.fondClair,
      barBackgroundColor:
          sombre ? RempartTokens.surfaceSombre : RempartTokens.surfaceClaire,
      textTheme: CupertinoTextThemeData(
        primaryColor: sombre ? RempartTokens.bleuClair : RempartTokens.bleu,
        // `inherit: false` partout : un style Cupertino part d'une feuille
        // blanche, sans quoi la taille et la graisse héritées du contexte
        // s'invitent dans les barres.
        textStyle: TextStyle(
          inherit: false,
          fontFamily: RempartTheme.police,
          color: texte,
          fontSize: 16,
          height: 1.35,
        ),
        navTitleTextStyle: TextStyle(
          inherit: false,
          fontFamily: RempartTheme.police,
          color: texte,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
        navLargeTitleTextStyle: TextStyle(
          inherit: false,
          fontFamily: RempartTheme.police,
          color: texte,
          fontSize: 30,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        navActionTextStyle: TextStyle(
          inherit: false,
          fontFamily: RempartTheme.police,
          color: sombre ? RempartTokens.bleuClair : RempartTokens.bleu,
          fontSize: 17,
        ),
        actionTextStyle: TextStyle(
          inherit: false,
          fontFamily: RempartTheme.police,
          color: sombre ? RempartTokens.bleuClair : RempartTokens.bleu,
          fontSize: 17,
        ),
        tabLabelTextStyle: TextStyle(
          inherit: false,
          fontFamily: RempartTheme.police,
          color: texte,
          // 11 et non 10 : c'est le plancher des consignes d'Apple, en dessous
          // duquel un libellé cesse d'être lisible d'un coup d'oeil.
          fontSize: 11,
          letterSpacing: -0.24,
        ),
        pickerTextStyle: TextStyle(
          inherit: false,
          fontFamily: RempartTheme.police,
          color: texte,
          fontSize: 21,
        ),
        dateTimePickerTextStyle: TextStyle(
          inherit: false,
          fontFamily: RempartTheme.police,
          color: texte,
          fontSize: 21,
        ),
      ),
    );
  }
}
