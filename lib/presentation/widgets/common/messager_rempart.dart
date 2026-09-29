import 'package:flutter/material.dart';

/// Hôte des bandeaux (`SnackBar`) de toute l'application, posé dans le
/// `builder` de `MaterialApp` comme de `CupertinoApp`.
///
/// Deux écarts au comportement de Flutter, faits ici une fois plutôt qu'à
/// chacun des appels (une quarantaine) :
/// - un bandeau **remplace** le précédent au lieu d'attendre derrière lui.
///   Cinq conversations supprimées d'affilée faisaient défiler cinq bandeaux
///   de quatre secondes, vingt secondes pendant lesquelles le bas de l'écran
///   restait couvert ;
/// - un appui sur le bandeau le ferme.
class MessagerRempart extends ScaffoldMessenger {
  const MessagerRempart({required super.child, super.key});

  @override
  ScaffoldMessengerState createState() => _MessagerRempartState();
}

class _MessagerRempartState extends ScaffoldMessengerState {
  @override
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showSnackBar(
    SnackBar snackBar, {
    AnimationStyle? snackBarAnimationStyle,
  }) {
    clearSnackBars();
    return super.showSnackBar(
      _fermableDUnAppui(snackBar),
      snackBarAnimationStyle: snackBarAnimationStyle,
    );
  }

  /// Le même bandeau, contenu enveloppé d'une zone qui le ferme. `SnackBar`
  /// n'a ni `onTap` ni `copyWith` : on recopie chaque champ, comme le fait
  /// Flutter lui-même dans `SnackBar.withAnimation`.
  SnackBar _fermableDUnAppui(SnackBar b) => SnackBar(
        key: b.key,
        content: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: hideCurrentSnackBar,
          child: b.content,
        ),
        backgroundColor: b.backgroundColor,
        elevation: b.elevation,
        margin: b.margin,
        padding: b.padding,
        width: b.width,
        shape: b.shape,
        hitTestBehavior: b.hitTestBehavior,
        behavior: b.behavior,
        action: b.action,
        actionOverflowThreshold: b.actionOverflowThreshold,
        showCloseIcon: b.showCloseIcon,
        closeIconColor: b.closeIconColor,
        duration: b.duration,
        persist: b.persist,
        animation: b.animation,
        onVisible: b.onVisible,
        dismissDirection: b.dismissDirection,
        clipBehavior: b.clipBehavior,
      );
}
