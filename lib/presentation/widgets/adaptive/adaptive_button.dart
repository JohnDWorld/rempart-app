
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../core/plateforme.dart';

/// Bouton principal adaptatif
class AdaptiveButton extends StatelessWidget {
  const AdaptiveButton({
    required this.onPressed,
    required this.child,
    this.isLoading = false,
    this.isDestructive = false,
    super.key,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final bool isLoading;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    if (estIOS) {
      return _buildCupertinoButton(context);
    }
    return _buildMaterialButton(context);
  }

  Widget _buildCupertinoButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: CupertinoButton.filled(
        onPressed: isLoading ? null : onPressed,
        child: isLoading
            ? CupertinoActivityIndicator(
                color: CupertinoTheme.of(context).primaryContrastingColor,
              )
            : child,
      ),
    );
  }

  Widget _buildMaterialButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton(
        onPressed: isLoading ? null : onPressed,
        style: isDestructive
            ? FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              )
            : null,
        child: isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator.adaptive(strokeWidth: 2),
              )
            : child,
      ),
    );
  }
}

/// Bouton texte adaptatif
class AdaptiveTextButton extends StatelessWidget {
  const AdaptiveTextButton({
    required this.onPressed,
    required this.child,
    super.key,
  });

  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (estIOS) {
      return CupertinoButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        child: child,
      );
    }
    return TextButton(
      onPressed: onPressed,
      child: child,
    );
  }
}

/// Bouton icône adaptatif
class AdaptiveIconButton extends StatelessWidget {
  const AdaptiveIconButton({
    required this.onPressed,
    required this.icon,
    this.tooltip,
    super.key,
  });

  final VoidCallback? onPressed;
  final Widget icon;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    if (estIOS) {
      return CupertinoButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        child: icon,
      );
    }
    return IconButton(
      onPressed: onPressed,
      icon: icon,
      tooltip: tooltip,
    );
  }
}
