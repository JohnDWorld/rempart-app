import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../app/theme.dart';

/// Widget avatar utilisateur avec indicateur de statut en ligne
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    required this.name,
    super.key,
    this.imageUrl,
    this.mxc,
    this.client,
    this.size = 48,
    this.isOnline,
    this.onTap,
    this.deleted = false,
  });

  final String name;
  final String? imageUrl;

  /// Avatar hébergé par Matrix (`mxc://`), utilisé faute de [imageUrl].
  ///
  /// C'est le widget qui résout l'URL, et non l'appelant : `getThumbnailUri`
  /// est asynchrone depuis le SDK 7, or appelé sans `await` il compile quand
  /// même (`Future.toString()`) et rend « Instance of `Future<Uri>` ». Tous les
  /// avatars venant de Matrix étaient ainsi des pastilles vides.
  final Uri? mxc;
  final Client? client;

  final double size;
  final bool? isOnline;
  final VoidCallback? onTap;

  /// Compte du correspondant supprimé : ni initiales (elles viendraient du
  /// localpart `u_<uuid>`, sans intérêt) ni couleur dérivée du nom. On affiche
  /// une silhouette barrée neutre.
  final bool deleted;

  @override
  Widget build(BuildContext context) {
    final mxc = this.mxc;
    final client = this.client;
    if (imageUrl == null && mxc != null && client != null) {
      final jeton = client.accessToken;
      return FutureBuilder<Uri>(
        // Miniature demandée au triple de la taille logique, pour rester nette
        // sur les écrans à forte densité.
        future: mxc.getThumbnailUri(client, width: size * 3, height: size * 3),
        builder: (context, snapshot) => _avatar(
          context,
          snapshot.data?.toString(),
          // Depuis Matrix 1.11 les médias ne sont plus servis en clair : le
          // SDK bascule seul sur l'endpoint authentifié, qui refuse une requête
          // sans jeton. L'en-tête est donc toujours envoyé ; l'ancien endpoint,
          // lui, l'ignore. Sans cela, mettre le serveur à jour viderait tous
          // les avatars.
          entetes: jeton == null ? null : {'Authorization': 'Bearer $jeton'},
        ),
      );
    }
    return _avatar(context, imageUrl);
  }

  Widget _avatar(
    BuildContext context,
    String? url, {
    Map<String, String>? entetes,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    // Couleur stable pour une même personne : deux teintes assorties, prises
    // dans la palette du thème plutôt que dans `Colors.primaries`, dont les
    // tons criards juraient avec le reste.
    final (clair, sombreEncre) =
        RempartTokens.avatars[name.hashCode.abs() % RempartTokens.avatars.length];
    // En thème sombre les rôles s'inversent : une pastille pastel sur fond
    // nuit éclabousse l'écran. On teinte la surface et on écrit en clair.
    final nuit = Theme.of(context).brightness == Brightness.dark;
    final fond = nuit
        ? Color.alphaBlend(
            sombreEncre.withValues(alpha: 0.38), colorScheme.surface)
        : clair;
    final encre = nuit ? clair : sombreEncre;
    final backgroundColor =
        deleted ? (nuit ? const Color(0xFF334155) : const Color(0xFFE2E8F0)) : fond;

    final initials = _getInitials(name);

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          // Avatar. Le dégradé très léger et le liseré intérieur suffisent à
          // décoller la pastille du fond : à plat, elle paraît collée.
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: url == null
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color.alphaBlend(
                          (nuit ? Colors.white : Colors.white)
                              .withValues(alpha: nuit ? 0.08 : 0.55),
                          backgroundColor,
                        ),
                        backgroundColor,
                      ],
                    )
                  : null,
              color: url == null ? null : backgroundColor,
              border: Border.all(
                color: nuit
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.05),
              ),
              image: url != null && !deleted
                  ? DecorationImage(
                      image: NetworkImage(url, headers: entetes),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: deleted
                ? Center(
                    child: Icon(
                      Icons.person_off_outlined,
                      size: size * 0.5,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  )
                : url == null
                    ? Center(
                        child: Text(
                          initials,
                          style: TextStyle(
                            fontFamily: RempartTheme.police,
                            fontSize: size * 0.36,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                            color: encre,
                          ),
                        ),
                      )
                    : null,
          ),

          // Indicateur en ligne
          if (isOnline != null)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: size * 0.3,
                height: size * 0.3,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isOnline! ? Colors.green : Colors.grey,
                  border: Border.all(
                    color: colorScheme.surface,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }
}
