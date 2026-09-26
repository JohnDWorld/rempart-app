
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../../../core/plateforme.dart';

/// Champ de texte adaptatif : CupertinoTextField sur iOS, TextField sur Android
class AdaptiveTextField extends StatelessWidget {
  const AdaptiveTextField({
    this.controller,
    this.placeholder,
    this.label,
    this.prefix,
    this.suffix,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.autofocus = false,
    this.autocorrect = true,
    this.maxLines = 1,
    this.onChanged,
    this.onSubmitted,
    this.validator,
    this.helperText,
    this.errorText,
    this.enabled = true,
    super.key,
  });

  final TextEditingController? controller;
  final String? placeholder;
  final String? label;
  final Widget? prefix;
  final Widget? suffix;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool autofocus;
  final bool autocorrect;
  final int? maxLines;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;
  final String? helperText;
  final String? errorText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (estIOS) {
      return _buildCupertinoTextField(context);
    }
    return _buildMaterialTextField(context);
  }

  Widget _buildCupertinoTextField(BuildContext context) {
    // Couleurs du thème de l'APPLICATION, aux jetons de la charte. Elles
    // suivaient `MediaQuery.platformBrightnessOf`, c'est-à-dire l'apparence
    // du système : l'utilisateur qui choisissait « Sombre » sur un téléphone
    // réglé en clair écrivait en noir sur un fond sombre, dans un champ gris
    // d'iOS au lieu de la surface de Rempart.
    final theme = Theme.of(context);
    final couleurs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final secondaire = isDark
        ? RempartTokens.texteSecondaireSombre
        : RempartTokens.texteSecondaireClair;

    final field = CupertinoTextField(
      controller: controller,
      placeholder: placeholder ?? label,
      prefix: prefix != null
          ? Padding(
              padding: const EdgeInsets.only(left: 8),
              child: prefix,
            )
          : null,
      suffix: suffix != null
          ? Padding(
              padding: const EdgeInsets.only(right: 8),
              child: suffix,
            )
          : null,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofocus: autofocus,
      autocorrect: autocorrect,
      maxLines: maxLines,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      enabled: enabled,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: isDark
            ? RempartTokens.surfaceEnfonceeSombre
            : RempartTokens.surfaceEnfonceeClaire,
        borderRadius: BorderRadius.circular(RempartTokens.rayonChamp),
      ),
      style: TextStyle(color: couleurs.onSurface),
      placeholderStyle: TextStyle(color: secondaire),
    );

    // Ajouter le label et les messages d'aide/erreur si nécessaires
    if (label != null || helperText != null || errorText != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            Text(
              label!,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: secondaire,
              ),
            ),
            const SizedBox(height: 6),
          ],
          field,
          if (errorText != null) ...[
            const SizedBox(height: 4),
            Text(
              errorText!,
              style: TextStyle(
                fontSize: 12,
                color: couleurs.error,
              ),
            ),
          ] else if (helperText != null) ...[
            const SizedBox(height: 4),
            Text(
              helperText!,
              style: TextStyle(
                fontSize: 12,
                color: secondaire,
              ),
            ),
          ],
        ],
      );
    }

    return field;
  }

  Widget _buildMaterialTextField(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: placeholder,
        prefixIcon: prefix,
        suffixIcon: suffix,
        helperText: helperText,
        errorText: errorText,
      ),
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofocus: autofocus,
      autocorrect: autocorrect,
      maxLines: maxLines,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      validator: validator,
      enabled: enabled,
    );
  }
}

/// Version FormField du CupertinoTextField pour validation
class AdaptiveTextFormField extends FormField<String> {
  AdaptiveTextFormField({
    super.key,
    this.controller,
    String? placeholder,
    String? label,
    Widget? prefix,
    Widget? suffix,
    bool obscureText = false,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    bool autofocus = false,
    bool autocorrect = true,
    int? maxLines = 1,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
    super.validator,
    String? helperText,
    bool enabled = true,
    super.initialValue,
    super.onSaved,
  }) : super(
          builder: (field) {
            final state = field as _AdaptiveTextFormFieldState;

            return AdaptiveTextField(
              controller: state._effectiveController,
              placeholder: placeholder,
              label: label,
              prefix: prefix,
              suffix: suffix,
              obscureText: obscureText,
              keyboardType: keyboardType,
              textInputAction: textInputAction,
              autofocus: autofocus,
              autocorrect: autocorrect,
              maxLines: maxLines,
              onChanged: (value) {
                field.didChange(value);
                onChanged?.call(value);
              },
              onSubmitted: onSubmitted,
              helperText: helperText,
              errorText: field.errorText,
              enabled: enabled,
            );
          },
        );

  final TextEditingController? controller;

  @override
  FormFieldState<String> createState() => _AdaptiveTextFormFieldState();
}

class _AdaptiveTextFormFieldState extends FormFieldState<String> {
  TextEditingController? _controller;

  TextEditingController get _effectiveController =>
      (widget as AdaptiveTextFormField).controller ?? _controller!;

  @override
  void initState() {
    super.initState();
    if ((widget as AdaptiveTextFormField).controller == null) {
      _controller = TextEditingController(text: widget.initialValue);
    }
  }

  @override
  void didUpdateWidget(AdaptiveTextFormField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget as AdaptiveTextFormField).controller != oldWidget.controller) {
      if (oldWidget.controller == null) {
        _controller?.dispose();
        _controller = null;
      }
      if ((widget as AdaptiveTextFormField).controller == null) {
        _controller = TextEditingController(text: value);
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  void reset() {
    super.reset();
    _effectiveController.text = widget.initialValue ?? '';
  }
}
