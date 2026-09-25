
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../../../core/plateforme.dart';
import '../../../data/models/matrix_extensions.dart';
import '../../../data/providers/providers.dart';
import '../../../data/services/archive_service.dart';
import '../../widgets/common/user_avatar.dart';

/// Écran affichant les conversations archivées
class ArchivedConversationsScreen extends ConsumerWidget {
  const ArchivedConversationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archivedRooms = ref.watch(archivedRoomsProvider);

    if (estIOS) {
      return _buildCupertinoScreen(context, ref, archivedRooms);
    }
    return _buildMaterialScreen(context, ref, archivedRooms);
  }

  Widget _buildCupertinoScreen(
    BuildContext context,
    WidgetRef ref,
    List<matrix.Room> rooms,
  ) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Archives'),
        leading: CupertinoNavigationBarBackButton(
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      child: SafeArea(
        child: rooms.isEmpty
            ? _buildEmptyState(context, isIOS: true)
            : ListView.builder(
                itemCount: rooms.length,
                itemBuilder: (context, index) {
                  final room = rooms[index];
                  return _buildArchivedTile(context, ref, room, isIOS: true);
                },
              ),
      ),
    );
  }

  Widget _buildMaterialScreen(
    BuildContext context,
    WidgetRef ref,
    List<matrix.Room> rooms,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Archives'),
      ),
      body: rooms.isEmpty
          ? _buildEmptyState(context, isIOS: false)
          : ListView.separated(
              itemCount: rooms.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final room = rooms[index];
                return _buildArchivedTile(context, ref, room, isIOS: false);
              },
            ),
    );
  }

  Widget _buildArchivedTile(
    BuildContext context,
    WidgetRef ref,
    matrix.Room room, {
    required bool isIOS,
  }) {
    // Le vrai nom, pas ce que la Room sait dire d'elle-même : hors d'un
    // groupe, `displayName` retombe sur le localpart du contact tant que ses
    // membres ne sont pas chargés, et la liste affichait « u_cac4cfdb... ».
    final nom = nomAffichable(ref, room);
    return ListTile(
      onTap: () => _showUnarchiveDialog(context, ref, room, isIOS: isIOS),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        radius: 28,
        backgroundColor: isIOS
            ? CupertinoColors.systemGrey4
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Text(
          initialesDe(nom).characters.first,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isIOS
                ? CupertinoColors.label
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      title: Text(
        nom,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        room.lastMessageText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isIOS
              ? CupertinoColors.systemGrey
              : Theme.of(context).colorScheme.outline,
        ),
      ),
      trailing: Icon(
        isIOS ? CupertinoIcons.archivebox : Icons.archive,
        color: isIOS
            ? CupertinoColors.systemGrey
            : Theme.of(context).colorScheme.outline,
      ),
    );
  }

  Future<void> _showUnarchiveDialog(
    BuildContext context,
    WidgetRef ref,
    matrix.Room room, {
    required bool isIOS,
  }) async {
    // Un seul `await`, posé sur la conditionnelle entière : avec un `await`
    // dans chaque branche, l'analyse de flot considère le `context` de la
    // seconde branche comme utilisé après un saut asynchrone
    // (use_build_context_synchronously), alors qu'une seule branche s'exécute.
    final shouldUnarchive = await (isIOS
        ? showCupertinoDialog<bool>(
            context: context,
            builder: (context) => CupertinoAlertDialog(
              title: const Text('Désarchiver'),
              content: Text(
                'Voulez-vous désarchiver la conversation avec '
                '"${nomAffichable(ref, room)}" ?',
              ),
              actions: [
                CupertinoDialogAction(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Annuler'),
                ),
                CupertinoDialogAction(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Désarchiver'),
                ),
              ],
            ),
          )
        : showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Désarchiver'),
              content: Text(
                'Voulez-vous désarchiver la conversation avec '
                '"${nomAffichable(ref, room)}" ?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Annuler'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Désarchiver'),
                ),
              ],
            ),
          ));

    if (shouldUnarchive ?? false) {
      await ArchiveService.instance.unarchiveRoom(room.id);
      ref.read(matrixStateNotifierProvider.notifier).state++;

      if (context.mounted) {
        _showMessage(
          context,
          'Conversation désarchivée',
          isIOS: isIOS,
        );
      }
    }
  }

  void _showMessage(BuildContext context, String message,
      {required bool isIOS}) {
    if (isIOS) {
      final overlay = OverlayEntry(
        builder: (context) => Positioned(
          bottom: MediaQuery.of(context).padding.bottom + 80,
          left: 16,
          right: 16,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: CupertinoColors.systemGrey.darkColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                message,
                style: const TextStyle(color: CupertinoColors.white),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );

      Overlay.of(context).insert(overlay);
      Future.delayed(const Duration(seconds: 2), overlay.remove);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildEmptyState(BuildContext context, {required bool isIOS}) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    final isDark = brightness == Brightness.dark;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isIOS ? CupertinoIcons.archivebox : Icons.archive_outlined,
            size: 80,
            color: isIOS
                ? CupertinoColors.systemGrey
                : Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'Aucune conversation archivée',
            style: isIOS
                ? TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color:
                        isDark ? CupertinoColors.white : CupertinoColors.black,
                  )
                : Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Les conversations archivées apparaîtront ici',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: isIOS
                  ? CupertinoColors.systemGrey
                  : Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
