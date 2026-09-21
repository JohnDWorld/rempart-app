
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../core/plateforme.dart';

/// ListTile adaptatif : CupertinoListTile sur iOS, ListTile sur Android
class AdaptiveListTile extends StatelessWidget {
  const AdaptiveListTile({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.contentPadding,
    super.key,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    if (estIOS) {
      return _buildCupertinoTile(context);
    }
    return _buildMaterialTile(context);
  }

  Widget _buildCupertinoTile(BuildContext context) {
    return CupertinoListTile.notched(
      title: title,
      subtitle: subtitle,
      leading: leading,
      trailing: trailing ?? const CupertinoListTileChevron(),
      onTap: onTap,
      padding: contentPadding as EdgeInsets?,
    );
  }

  Widget _buildMaterialTile(BuildContext context) {
    return ListTile(
      title: title,
      subtitle: subtitle,
      leading: leading,
      trailing: trailing,
      onTap: onTap,
      contentPadding: contentPadding,
    );
  }
}

/// SwitchListTile adaptatif
class AdaptiveSwitchListTile extends StatelessWidget {
  const AdaptiveSwitchListTile({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.secondary,
    super.key,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? secondary;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    if (estIOS) {
      return _buildCupertinoTile(context);
    }
    return _buildMaterialTile(context);
  }

  Widget _buildCupertinoTile(BuildContext context) {
    return CupertinoListTile.notched(
      title: title,
      subtitle: subtitle,
      leading: secondary,
      trailing: CupertinoSwitch(
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildMaterialTile(BuildContext context) {
    return SwitchListTile(
      title: title,
      subtitle: subtitle,
      secondary: secondary,
      value: value,
      onChanged: onChanged,
    );
  }
}
