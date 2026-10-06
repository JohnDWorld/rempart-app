import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../../../core/utils/lectures.dart';
import '../../../data/models/matrix_extensions.dart';
import '../../../data/providers/providers.dart';
import '../common/user_avatar.dart';

/// Quand un de mes messages est parti, et qui l'a lu.
///
/// Matrix ne dit pas quand un message ARRIVE sur le téléphone d'en face : il
/// n'a pas d'équivalent du « distribué » de WhatsApp. La fiche s'en tient donc
/// à ce qu'il sait, l'envoi et les lectures, plutôt que d'afficher une ligne
/// qu'elle ne pourrait pas remplir honnêtement. Qui garde ses accusés de
/// lecture privés reste « pas encore lu ».
class InformationsMessage extends ConsumerWidget {
  const InformationsMessage({required this.event, super.key});

  final matrix.Event event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = event.room;
    final theme = Theme.of(context);
    return SafeArea(
      // Les membres d'un salon ne sont pas forcément en mémoire au démarrage :
      // on les demande, sans quoi un groupe paraîtrait n'avoir aucun lecteur.
      child: FutureBuilder<List<matrix.User>>(
        future: room.requestParticipants([matrix.Membership.join]),
        builder: (context, membres) {
          final moi = room.client.userID;
          final destinataires = [
            for (final membre in membres.data ?? const <matrix.User>[])
              if (membre.id != moi) membre.id,
          ];
          final lectures = lecturesDe(
            envoye: event.originServerTs,
            accuses: room.derniersAccuses,
            destinataires: destinataires,
          );
          final maintenant = DateTime.now();

          return ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('Informations', style: theme.textTheme.titleMedium),
              ),
              ListTile(
                leading: const Icon(Icons.done),
                title: const Text('Envoyé'),
                subtitle: Text(dateComplete(event.originServerTs)),
              ),
              if (!membres.hasData)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator.adaptive()),
                )
              else if (destinataires.length == 1)
                ListTile(
                  leading: Icon(
                    Icons.done_all,
                    color: lectures.lu.isEmpty ? null : theme.colorScheme.primary,
                  ),
                  title: Text(lectures.lu.isEmpty ? 'Pas encore lu' : 'Lu'),
                  subtitle: lectures.lu.isEmpty
                      ? null
                      : Text(quandLisible(lectures.lu.single.quand, maintenant)),
                )
              else ...[
                if (lectures.lu.isNotEmpty) ...[
                  _Titre('Lu par', theme),
                  for (final lecture in lectures.lu)
                    _Personne(
                      mxid: lecture.mxid,
                      room: room,
                      precision: quandLisible(lecture.quand, maintenant),
                    ),
                ],
                if (lectures.pasLu.isNotEmpty) ...[
                  _Titre('Pas encore lu', theme),
                  for (final mxid in lectures.pasLu)
                    _Personne(mxid: mxid, room: room),
                ],
              ],
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }
}

class _Titre extends StatelessWidget {
  const _Titre(this.texte, this.theme);

  final String texte;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Text(
          texte,
          style: theme.textTheme.labelLarge
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
}

/// Une personne, par son nom (jamais par son identifiant).
class _Personne extends ConsumerWidget {
  const _Personne({required this.mxid, required this.room, this.precision});

  final String mxid;
  final matrix.Room room;
  final String? precision;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nom = ref.watch(nomContactProvider(mxid)) ?? 'Contact inconnu';
    return ListTile(
      leading: UserAvatar(
        name: nom,
        mxc: room.unsafeGetUserFromMemoryOrFallback(mxid).avatarUrl,
        client: room.client,
        size: 36,
      ),
      title: Text(nom),
      trailing: precision == null ? null : Text(precision!),
    );
  }
}
