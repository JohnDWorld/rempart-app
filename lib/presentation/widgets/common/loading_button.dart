import 'package:flutter/material.dart';

/// Bouton avec indicateur de chargement intégré
class LoadingButton extends StatelessWidget {
  const LoadingButton({
    required this.onPressed,
    required this.child,
    super.key,
    this.isLoading = false,
    this.style,
    this.width,
  });

  /// Callback appelé quand le bouton est pressé
  final VoidCallback? onPressed;

  /// Indique si le bouton est en état de chargement
  final bool isLoading;

  /// Contenu du bouton
  final Widget child;

  /// Style du bouton (optionnel)
  final ButtonStyle? style;

  /// Largeur du bouton (optionnel, par défaut double.infinity)
  final double? width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width ?? double.infinity,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: style,
        child: isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator.adaptive(
                  strokeWidth: 2,
                ),
              )
            : child,
      ),
    );
  }
}

/// Bouton outline avec indicateur de chargement
class LoadingOutlinedButton extends StatelessWidget {
  const LoadingOutlinedButton({
    required this.onPressed,
    required this.child,
    super.key,
    this.isLoading = false,
    this.style,
    this.width,
  });

  final VoidCallback? onPressed;
  final bool isLoading;
  final Widget child;
  final ButtonStyle? style;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width ?? double.infinity,
      child: OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: style,
        child: isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator.adaptive(
                  strokeWidth: 2,
                ),
              )
            : child,
      ),
    );
  }
}
