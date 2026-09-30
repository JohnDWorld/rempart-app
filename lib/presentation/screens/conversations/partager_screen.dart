import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../../../app/theme.dart';
import '../../../data/providers/providers.dart';
import '../../../data/services/partage_entrant.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/conversations/conversation_tile.dart';

/// « Envoyer à… » : choix de la conversation qui recevra ce qu'une autre
/// application vient de partager.
///
/// Le choix fait, la conversation s'ouvre sur l'aperçu d'envoi habituel
/// (légende, qualité) : le partage passe ensuite par le même chemin qu'une
/// pièce jointe, chiffrement vérifié compris.
class PartagerScreen extends ConsumerStatefulWidget {
  const PartagerScreen({super.key});

  @override
  ConsumerState<PartagerScreen> createState() => _PartagerScreenState();
}

class _PartagerScreenState extends ConsumerState<PartagerScreen> {
  String _recherche = '';

  @override
  void dispose() {
    // Revenu en arrière sans choisir : le partage est abandonné, et ne doit
    // pas se proposer à nouveau au prochain passage par l'accueil.
    PartageEntrant.instance.enAttente.value = null;
    super.dispose();
  }

  void _envoyerA(matrix.Room room) {
    final partage = PartageEntrant.instance.prendre();
    if (partage == null) return;
    // L'écran de choix n'a plus lieu d'être sous la conversation.
    context.pushReplacement('/chat/${room.id}', extra: partage);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _recherche.trim().toLowerCase();
    final rooms = [
      for (final room in ref.watch(sortedRoomsProvider))
        if (q.isEmpty || nomAffichable(ref, room).toLowerCase().contains(q))
          room,
    ];

    return AdaptiveScaffold(
      title: 'Envoyer à…',
      body: ValueListenableBuilder<Partage?>(
        valueListenable: PartageEntrant.instance.enAttente,
        builder: (context, partage, _) {
          if (partage == null) {
            return const Center(child: Text('Rien à envoyer'));
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  RempartTokens.espaceL,
                  RempartTokens.espaceS,
                  RempartTokens.espaceL,
                  0,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.attach_file,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        resumePartage(
                          [for (final f in partage.fichiers) f.type],
                          partage.texte,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(RempartTokens.espaceL),
                child: TextField(
                  onChanged: (valeur) => setState(() => _recherche = valeur),
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: 'Rechercher une conversation',
                    prefixIcon: Icon(Icons.search, size: 22),
                    isDense: true,
                  ),
                ),
              ),
              Expanded(
                child: rooms.isEmpty
                    ? const Center(child: Text('Aucune conversation'))
                    : ListView.builder(
                        itemCount: rooms.length,
                        itemBuilder: (context, index) => ConversationTile(
                          room: rooms[index],
                          onTap: () => _envoyerA(rooms[index]),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
