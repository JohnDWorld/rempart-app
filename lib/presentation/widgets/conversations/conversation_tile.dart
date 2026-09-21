import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../../../app/theme.dart';
import '../../../data/models/matrix_extensions.dart';
import '../../../data/providers/providers.dart';
import '../adaptive/adaptive.dart';
import '../common/deleted_account_badge.dart';
import '../common/encryption_badge.dart';
import '../common/user_avatar.dart';

/// Actions proposées à l'appui long sur une conversation.
enum _TileAction { archive, delete }

/// Tuile représentant une conversation (room Matrix) dans la liste
class ConversationTile extends ConsumerWidget {
  const ConversationTile({
    required this.room,
    required this.onTap,
    this.onArchive,
    this.confirmArchive,
    this.onDelete,
    this.confirmDelete,
    super.key,
  });

  final matrix.Room room;
  final VoidCallback onTap;
  final VoidCallback? onArchive;
  final Future<bool> Function()? confirmArchive;
  final VoidCallback? onDelete;
  final Future<bool> Function()? confirmDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Le mxid du contact est relu à chaque build : la Room est mutable hors du
    // graphe Riverpod, le mémoriser figerait un état antérieur au chargement de
    // ses membres. Seule la résolution Supabase passe par un provider.
    final contactMxid = room.otherUserMxid;
    final contact = contactMxid == null
        ? null
        : ref.watch(contactProfileProvider(contactMxid)).value;
    final deleted = contact?.deleted ?? false;
    final title = contact?.name ?? room.displayName;
    // Le compteur du serveur, tempéré par ce qu'on vient de lire : sans cela,
    // une conversation qu'on quitte à l'instant reste en gras jusqu'au sync
    // suivant, comme si l'ouverture n'avait pas compté.
    final dernierLu = ref.watch(derniersLusProvider)[room.id];
    final hasUnread = room.unreadCount > 0 &&
        (dernierLu == null || room.lastEvent?.eventId != dernierLu);

    // Sur un écran large, la souris révèle ce que le doigt ne voyait pas :
    // le fond de survol courait jusqu'aux deux bords du panneau et s'y
    // collait. Quatre points de retrait de chaque côté le détachent, et le
    // contenu recule d'autant à l'intérieur pour ne pas bouger d'un point,
    // filets de séparation compris. Le téléphone n'a pas de survol : rien
    // n'y change.
    final retrait =
        MediaQuery.sizeOf(context).width >= RempartTokens.seuilEcranLarge
            ? 4.0
            : 0.0;

    final tile = Padding(
      padding: EdgeInsets.symmetric(horizontal: retrait),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: _hasActions ? () => _showActions(context) : null,
          // Le halo de pression suit un rectangle arrondi encarté : sur toute la
          // largeur, il donne l'impression d'un bandeau, pas d'un élément.
          borderRadius: BorderRadius.circular(RempartTokens.rayonCarte),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: RempartTokens.espaceL - retrait,
              vertical: RempartTokens.espaceM,
            ),
            child: Row(
              children: [
                _buildAvatar(context, title, contact?.avatarUrl, deleted),
                const SizedBox(width: RempartTokens.espaceM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          EncryptionBadge(room: room, size: 13),
                          const SizedBox(width: RempartTokens.espaceXs),
                          Expanded(
                            // Compte supprimé : le nom retomberait sur le
                            // localpart `u_<uuid>`, illisible et sans valeur pour
                            // l'utilisateur. La pastille dit déjà tout.
                            child: deleted
                                ? const Align(
                                    alignment: Alignment.centerLeft,
                                    child: DeletedAccountBadge(),
                                  )
                                : Text(
                                    title,
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: hasUnread
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                          ),
                          if (room.lastMessageTime != null) ...[
                            const SizedBox(width: RempartTokens.espaceS),
                            Text(
                              _formatTime(room.lastMessageTime!),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: hasUnread
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                                fontWeight: hasUnread
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              room.lastMessageText,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: hasUnread
                                    ? theme.colorScheme.onSurface
                                    : theme.colorScheme.onSurfaceVariant,
                                fontWeight: hasUnread
                                    ? FontWeight.w500
                                    : FontWeight.w400,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (hasUnread) ...[
                            const SizedBox(width: RempartTokens.espaceS),
                            _PastilleNonLus(nombre: room.unreadCount),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Swipe : vers la gauche = archiver, vers la droite = supprimer.
    final canArchive = onArchive != null;
    final canDelete = onDelete != null;
    if (!canArchive && !canDelete) {
      return tile;
    }

    final DismissDirection direction;
    if (canArchive && canDelete) {
      direction = DismissDirection.horizontal;
    } else if (canArchive) {
      direction = DismissDirection.endToStart;
    } else {
      direction = DismissDirection.startToEnd;
    }

    return Dismissible(
      key: Key(room.id),
      direction: direction,
      // startToEnd (glissé vers la droite) : supprimer.
      background: canDelete
          ? _FondGlisse(
              alignement: Alignment.centerLeft,
              couleur: theme.colorScheme.error,
              icone: Icons.delete_outline,
              libelle: 'Supprimer',
            )
          : const SizedBox.shrink(),
      // endToStart (glissé vers la gauche) : archiver.
      secondaryBackground: canArchive
          ? _FondGlisse(
              alignement: Alignment.centerRight,
              couleur: theme.colorScheme.secondary,
              icone: Icons.archive_outlined,
              libelle: 'Archiver',
            )
          : null,
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          return confirmDelete == null || await confirmDelete!();
        }
        return confirmArchive == null || await confirmArchive!();
      },
      onDismissed: (dir) {
        if (dir == DismissDirection.startToEnd) {
          onDelete?.call();
        } else {
          onArchive?.call();
        }
      },
      child: tile,
    );
  }

  /// Y a-t-il au moins une action à proposer à l'appui long ?
  bool get _hasActions => onArchive != null || onDelete != null;

  /// Menu d'actions à l'appui long : le glissé (archiver/supprimer) n'est pas
  /// découvrable, on expose donc les mêmes actions explicitement.
  Future<void> _showActions(BuildContext context) async {
    final action = await feuilleAdaptative<_TileAction>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onArchive != null)
              ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: const Text('Archiver'),
                onTap: () => Navigator.pop(sheetContext, _TileAction.archive),
              ),
            if (onDelete != null)
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
                title: Text(
                  'Supprimer',
                  style: TextStyle(
                    color: Theme.of(sheetContext).colorScheme.error,
                  ),
                ),
                onTap: () => Navigator.pop(sheetContext, _TileAction.delete),
              ),
          ],
        ),
      ),
    );

    if (action == null) return;
    // Mêmes confirmations que le glissé : on ne détruit rien sans validation.
    if (action == _TileAction.archive) {
      if (confirmArchive == null || await confirmArchive!()) onArchive?.call();
    } else {
      if (confirmDelete == null || await confirmDelete!()) onDelete?.call();
    }
  }

  Widget _buildAvatar(
    BuildContext context,
    String title,
    String? profileUrl,
    bool deleted,
  ) {
    // Priorité à l'avatar du profil Supabase (source de vérité des profils),
    // repli sur l'avatar Matrix de la room.
    return UserAvatar(
      name: title,
      imageUrl: profileUrl,
      mxc: room.avatarUri,
      client: room.client,
      size: 56,
      deleted: deleted,
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      return DateFormat.Hm().format(dateTime);
    } else if (difference.inDays == 1) {
      return 'Hier';
    } else if (difference.inDays < 7) {
      return DateFormat.E('fr').format(dateTime);
    } else {
      return DateFormat.MMMd('fr').format(dateTime);
    }
  }
}

/// Compteur de messages non lus.
class _PastilleNonLus extends StatelessWidget {
  const _PastilleNonLus({required this.nombre});

  final int nombre;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(999),
        boxShadow: RempartTokens.ombreLegere(theme.brightness),
      ),
      child: Text(
        nombre > 99 ? '99+' : '$nombre',
        textAlign: TextAlign.center,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimary,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }
}

/// Fond révélé par le glissé : couleur pleine, icône et intention écrite.
///
/// Le libellé n'est pas décoratif : une icône seule laisse hésiter sur le sens
/// du geste, et se tromper de côté détruit une conversation.
class _FondGlisse extends StatelessWidget {
  const _FondGlisse({
    required this.alignement,
    required this.couleur,
    required this.icone,
    required this.libelle,
  });

  final Alignment alignement;
  final Color couleur;
  final IconData icone;
  final String libelle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      alignment: alignement,
      padding: const EdgeInsets.symmetric(horizontal: RempartTokens.espaceXl),
      color: couleur,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, color: Colors.white, size: 22),
          const SizedBox(width: RempartTokens.espaceS),
          Text(
            libelle,
            style: theme.textTheme.labelLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
