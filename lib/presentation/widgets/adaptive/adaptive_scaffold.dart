
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../core/plateforme.dart';

/// Un Scaffold adaptatif qui utilise CupertinoPageScaffold sur iOS
/// et Scaffold standard sur Android/autres plateformes
class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({
    required this.body,
    this.title,
    this.titleWidget,
    this.leading,
    this.trailing,
    this.actions,
    this.floatingActionButton,
    this.backgroundColor,
    this.previousPageTitle,
    super.key,
  });

  final Widget body;
  final String? title;
  final Widget? titleWidget;
  final Widget? leading;
  final Widget? trailing;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Color? backgroundColor;
  final String? previousPageTitle;

  @override
  Widget build(BuildContext context) {
    if (estIOS) {
      return _buildCupertinoScaffold(context);
    }
    return _buildMaterialScaffold(context);
  }

  Widget _buildCupertinoScaffold(BuildContext context) {
    // Couleurs laissées au `CupertinoTheme`, qui dérive des mêmes jetons que
    // le thème Material. Elles étaient auparavant forcées à
    // `CupertinoColors.systemBackground`, dont la variante sombre est un NOIR
    // pur : la page tranchait avec les cartes en bleu nuit posées dessus.
    return CupertinoPageScaffold(
      backgroundColor: backgroundColor,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: backgroundColor,
        middle: titleWidget ?? (title != null ? Text(title!) : null),
        leading: leading,
        trailing: trailing ?? _buildCupertinoActions(),
        previousPageTitle: previousPageTitle,
      ),
      // Un `Scaffold` transparent sous la barre Cupertino : il n'ajoute aucun
      // décor, mais il donne un hôte aux `SnackBar`. Sans lui, tout appel à
      // `ScaffoldMessenger` depuis ces écrans échoue sur iOS, faute de
      // `Scaffold` enregistré - et une bonne partie des écrans récents
      // signalent leurs succès et leurs erreurs exactement comme ça.
      //
      // `resizeToAvoidBottomInset: false` : c'est le `CupertinoPageScaffold`
      // qui gère déjà la remontée au clavier, inutile de la faire deux fois.
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          child: Stack(
            children: [
              body,
              if (floatingActionButton != null)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: floatingActionButton!,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _buildCupertinoActions() {
    if (actions == null || actions!.isEmpty) return null;
    if (actions!.length == 1) return actions!.first;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: actions!,
    );
  }

  Widget _buildMaterialScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: (title != null || titleWidget != null || actions != null)
          ? AppBar(
              title: titleWidget ?? (title != null ? Text(title!) : null),
              leading: leading,
              actions: actions,
            )
          : null,
      body: body,
      floatingActionButton: floatingActionButton,
    );
  }
}
