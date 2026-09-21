import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../../../app/theme.dart';

/// Petit cadenas indiquant l'état de chiffrement d'une room.
///
/// Chiffré = cadenas fermé vert (chat sécurisé E2E).
/// Non chiffré = cadenas ouvert (lisible par le serveur, ex. chat avec bot).
class EncryptionBadge extends StatelessWidget {
  const EncryptionBadge({required this.room, this.size = 14, super.key});

  final matrix.Room room;
  final double size;

  @override
  Widget build(BuildContext context) {
    final encrypted = room.encrypted;
    return Icon(
      encrypted ? Icons.lock : Icons.lock_open,
      size: size,
      color: encrypted
          ? RempartTokens.texteSucces(Theme.of(context).brightness)
          : Theme.of(context).colorScheme.outline,
      semanticLabel: encrypted
          ? 'Chiffré de bout en bout'
          : 'Non chiffré, lisible par le serveur',
    );
  }
}

/// Bandeau persistant en haut d'un chat, explicitant l'état de chiffrement.
class EncryptionBanner extends StatelessWidget {
  const EncryptionBanner({required this.room, this.avecFond = true, super.key});

  final matrix.Room room;

  /// Faux quand le bandeau est posé dans une pastille qui porte déjà son
  /// propre fond : sans cela, deux fonds se superposent.
  final bool avecFond;

  @override
  Widget build(BuildContext context) {
    final encrypted = room.encrypted;
    final theme = Theme.of(context);
    final color = encrypted
        ? RempartTokens.texteSucces(theme.brightness)
        : theme.colorScheme.onSurfaceVariant;

    return Container(
      width: avecFond ? double.infinity : null,
      color: !avecFond
          ? null
          : encrypted
              // La teinte du texte à 10 %, et non un vert à part : c'est sur
              // ce fond précis que le contraste a été mesuré (5,77:1 en clair,
              // 9,03:1 en sombre).
              ? color.withValues(alpha: 0.10)
              : theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisSize: avecFond ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            encrypted ? Icons.lock : Icons.lock_open,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              encrypted
                  ? 'Messages chiffrés de bout en bout'
                  : 'Non chiffré · lisible par le serveur Rempart',
              style: theme.textTheme.bodySmall?.copyWith(color: color),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
