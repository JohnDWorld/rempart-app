
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../../../core/plateforme.dart';

/// Affiche une alerte adaptative
Future<T?> showAdaptiveAlert<T>({
  required BuildContext context,
  required String title,
  required String content,
  String? cancelText,
  String? confirmText,
  bool isDestructive = false,
}) {
  if (estIOS) {
    return showCupertinoDialog<T>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          if (cancelText != null)
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: Text(cancelText),
            ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, true as T),
            isDestructiveAction: isDestructive,
            child: Text(confirmText ?? 'OK'),
          ),
        ],
      ),
    );
  }

  return showDialog<T>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        if (cancelText != null)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(cancelText),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, true as T),
          style: isDestructive
              ? TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                )
              : null,
          child: Text(confirmText ?? 'OK'),
        ),
      ],
    ),
  );
}

/// Affiche un bottom sheet adaptatif (ActionSheet sur iOS)
Future<T?> showAdaptiveActionSheet<T>({
  required BuildContext context,
  required List<AdaptiveAction<T>> actions,
  String? title,
  String? message,
  AdaptiveAction<T>? cancelAction,
}) {
  if (estIOS) {
    return showCupertinoModalPopup<T>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: title != null ? Text(title) : null,
        message: message != null ? Text(message) : null,
        actions: actions.map((action) {
          return CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context, action.value);
              action.onPressed?.call();
            },
            isDestructiveAction: action.isDestructive,
            child: Text(action.label),
          );
        }).toList(),
        cancelButton: cancelAction != null
            ? CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.pop(context);
                  cancelAction.onPressed?.call();
                },
                child: Text(cancelAction.label),
              )
            : null,
      ),
    );
  }

  return showModalBottomSheet<T>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ...actions.map((action) {
            return ListTile(
              leading: action.icon,
              title: Text(
                action.label,
                style: action.isDestructive
                    ? TextStyle(color: Theme.of(context).colorScheme.error)
                    : null,
              ),
              onTap: () {
                Navigator.pop(context, action.value);
                action.onPressed?.call();
              },
            );
          }),
          if (cancelAction != null)
            ListTile(
              title: Text(cancelAction.label),
              onTap: () {
                Navigator.pop(context);
                cancelAction.onPressed?.call();
              },
            ),
        ],
      ),
    ),
  );
}

/// Action pour les action sheets
class AdaptiveAction<T> {
  const AdaptiveAction({
    required this.label,
    this.value,
    this.icon,
    this.onPressed,
    this.isDestructive = false,
  });

  final String label;
  final T? value;
  final Widget? icon;
  final VoidCallback? onPressed;
  final bool isDestructive;
}

/// Une feuille remontée du bas sur un téléphone, une fenêtre centrée ailleurs.
///
/// La feuille du bas est le geste d'un pouce : elle arrive là où il se trouve
/// déjà. Sur un écran de bureau, la même feuille traverse toute la largeur
/// pour trois lignes de contenu, et oblige à descendre au bas de la fenêtre
/// pour choisir. Posée au centre et bornée, la même liste se lit d'un coup
/// d'oeil et se clique là où le regard est déjà.
///
/// Les paramètres reprennent ceux de `showModalBottomSheet` : passer de l'un à
/// l'autre ne demande que de changer le nom.
Future<T?> feuilleAdaptative<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool showDragHandle = false,
  bool isScrollControlled = false,
}) {
  if (MediaQuery.sizeOf(context).width < RempartTokens.seuilEcranLarge) {
    return showModalBottomSheet<T>(
      context: context,
      showDragHandle: showDragHandle,
      isScrollControlled: isScrollControlled,
      builder: builder,
    );
  }
  return showDialog<T>(
    context: context,
    builder: (context) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        // Bornée des deux côtés : aussi large que l'écran, une fenêtre ne
        // vaudrait pas mieux qu'une feuille, et un contenu plus haut que la
        // page doit défiler dedans plutôt que déborder.
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: builder(context),
      ),
    ),
  );
}
