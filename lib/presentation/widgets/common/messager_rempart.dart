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

/// [MessagerRempart], prêt à poser sous `CupertinoApp`.
///
/// En mode debug, `ScaffoldMessenger.of` vérifie qu'un ancêtre est de type
/// **exactement** `ScaffoldMessenger` (`debugCheckHasScaffoldMessenger`), ce
/// qu'une sous-classe ne satisfait pas. Sous `MaterialApp`, celui que pose
/// l'application passe le contrôle ; `CupertinoApp` n'en pose aucun, et chaque
/// bandeau levait « No ScaffoldMessenger widget found » sur iPhone (vu le
/// 2026-10-27 sur « Modifier le profil »). La version de production, sans
/// vérification, l'affichait quand même : seul le simulateur le montrait.
///
/// Un `ScaffoldMessenger` ordinaire au-dessus suffit : il passe le contrôle, et
/// `ScaffoldMessenger.of` rend toujours le plus proche, donc celui-ci.
class MessagerRempartCupertino extends StatelessWidget {
  const MessagerRempartCupertino({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ScaffoldMessenger(child: MessagerRempart(child: child));
}
