import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';

import '../../../data/models/matrix_extensions.dart';
import '../../../data/providers/providers.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/common/user_avatar.dart';

/// Fiche d'un groupe, ouverte en touchant son nom dans l'en-tête de la
/// conversation : sujet, membres, et administration du groupe.
///
/// Chaque action n'apparaît que si le serveur l'autoriserait : les droits sont
/// lus dans les niveaux de pouvoir de la room (`canInvite`, `canKick`,
/// `canChangeStateEvent`). Un bouton qui finirait en M_FORBIDDEN serait une
/// promesse non tenue.
class GroupInfoScreen extends ConsumerWidget {
  const GroupInfoScreen({required this.roomId, super.key});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = ref.watch(roomProvider(roomId));
    if (room == null) {
      return const AdaptiveScaffold(
        title: 'Informations',
        body: Center(child: Text('Conversation introuvable')),
      );
    }

    // La Room est mutable hors du graphe Riverpod. Le compteur suit les actions
    // locales, mais un renommage n'est visible qu'au retour de l'événement
    // d'état : sans écouter le sync, l'écran garderait l'ancien nom (la liste
    // des conversations, elle, se remettait à jour).
    ref
      ..watch(matrixStateNotifierProvider)
      ..watch(syncTickProvider);

    final client = ref.watch(matrixClientProvider);
    final membres = ref.watch(roomMembersProvider(roomId));
    final peutRenommer = room.canChangeStateEvent(EventTypes.RoomName);
    final peutChangerSujet = room.canChangeStateEvent(EventTypes.RoomTopic);
    final peutChangerPhoto = room.canChangeStateEvent(EventTypes.RoomAvatar);

    return AdaptiveScaffold(
      title: 'Informations',
      previousPageTitle: 'Retour',
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        children: [
          Center(
            child: UserAvatar(
              name: room.displayName,
              mxc: room.avatarUri,
              client: client,
              size: 96,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                room.displayName,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
          if (room.topic.isNotEmpty) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(room.topic, textAlign: TextAlign.center),
            ),
          ],
          const SizedBox(height: 24),
          if (peutChangerPhoto)
            AdaptiveListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(
                room.avatarUri == null
                    ? 'Ajouter une photo'
                    : 'Changer la photo',
              ),
              onTap: () => _changerPhoto(context, ref, room),
            ),
          if (peutRenommer)
            AdaptiveListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Renommer le groupe'),
              onTap: () => _renommer(context, ref, room),
            ),
          if (peutChangerSujet)
            AdaptiveListTile(
              leading: const Icon(Icons.subject),
              title: Text(
                room.topic.isEmpty ? 'Ajouter un sujet' : 'Modifier le sujet',
              ),
              onTap: () => _changerSujet(context, ref, room),
            ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              membres.when(
                data: (liste) => '${liste.length} membres',
                loading: () => 'Membres',
                error: (_, __) => 'Membres',
              ),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          if (room.canInvite)
            AdaptiveListTile(
              leading: const Icon(Icons.person_add_alt),
              title: const Text('Ajouter des membres'),
              onTap: () =>
                  context.push('/group/${Uri.encodeComponent(roomId)}/add'),
            ),
          ...membres.when(
            data: (liste) => _trier(liste).map(
              (membre) => _TuileMembre(
                membre: membre,
                estMoi: membre.id == client?.userID,
                roomId: roomId,
              ),
            ),
            loading: () => [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator.adaptive()),
              ),
            ],
            // Hors ligne, la liste des membres peut ne pas être complétable :
            // le dire plutôt que d'afficher un groupe qui semblerait vide.
            error: (e, _) => [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Liste des membres indisponible'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          AdaptiveListTile(
            leading: Icon(
              Icons.logout,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Quitter le groupe',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: () => _quitter(context, ref),
          ),
          // Supprimer exige de pouvoir renvoyer les autres : sans ce droit, le
          // bouton ne ferait que quitter, sous un nom trompeur.
          if (room.canKick)
            AdaptiveListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Supprimer le groupe',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => _supprimer(context, ref),
            ),
        ],
      ),
    );
  }

  /// Les responsables du groupe en tête, puis par ordre alphabétique.
  List<User> _trier(List<User> membres) {
    final tries = [...membres]..sort((a, b) {
        final niveau = b.powerLevel.level.compareTo(a.powerLevel.level);
        if (niveau != 0) return niveau;
        return a.calcDisplayname().toLowerCase().compareTo(
              b.calcDisplayname().toLowerCase(),
            );
      });
    return tries;
  }

  Future<void> _renommer(
    BuildContext context,
    WidgetRef ref,
    Room room,
  ) async {
    final nom = await demanderTexte(
      context: context,
      titre: 'Renommer le groupe',
      valeurInitiale: room.name,
      placeholder: 'Nom du groupe',
      valider: 'Renommer',
    );
    if (nom == null || nom.isEmpty || nom == room.name) return;
    if (!context.mounted) return;
    await _appliquer(
      context,
      ref,
      () => ref.read(matrixServiceProvider).renommerRoom(room.id, nom),
      'Renommage impossible',
    );
  }

  Future<void> _changerSujet(
    BuildContext context,
    WidgetRef ref,
    Room room,
  ) async {
    final sujet = await demanderTexte(
      context: context,
      titre: 'Sujet du groupe',
      valeurInitiale: room.topic,
      placeholder: 'De quoi parle ce groupe ?',
      valider: 'Enregistrer',
      lignes: 3,
    );
    if (sujet == null || sujet == room.topic) return;
    if (!context.mounted) return;
    await _appliquer(
      context,
      ref,
      () => ref.read(matrixServiceProvider).changerSujetRoom(room.id, sujet),
      'Modification du sujet impossible',
    );
  }

  /// Choisit une photo de groupe, ou retire celle en place.
  ///
  /// Même chemin que les pièces jointes du chat : `MatrixFile.fromMimeType`
  /// laisse le SDK déduire le type d'après le contenu.
  Future<void> _changerPhoto(
    BuildContext context,
    WidgetRef ref,
    Room room,
  ) async {
    final avaitUnePhoto = room.avatarUri != null;
    final source = await showAdaptiveActionSheet<String>(
      context: context,
      title: 'Photo du groupe',
      actions: [
        const AdaptiveAction(label: 'Depuis la galerie', value: 'galerie'),
        const AdaptiveAction(label: 'Appareil photo', value: 'camera'),
        if (avaitUnePhoto)
          const AdaptiveAction(
            label: 'Retirer la photo',
            value: 'retirer',
            isDestructive: true,
          ),
      ],
      cancelAction: const AdaptiveAction(label: 'Annuler'),
    );
    if (source == null || !context.mounted) return;

    MatrixFile? fichier;
    if (source != 'retirer') {
      final choisi = source == 'camera'
          ? await ImagePicker().pickImage(source: ImageSource.camera)
          : await ImagePicker().pickImage(source: ImageSource.gallery);
      if (choisi == null) return;
      fichier = MatrixFile.fromMimeType(
        bytes: await choisi.readAsBytes(),
        name: choisi.name,
        mimeType: choisi.mimeType,
      );
    }
    if (!context.mounted) return;

    await _appliquer(
      context,
      ref,
      () => ref.read(matrixServiceProvider).changerAvatarRoom(room.id, fichier),
      'Changement de photo impossible',
    );
  }

  Future<void> _quitter(BuildContext context, WidgetRef ref) async {
    final confirme = await showAdaptiveAlert<bool>(
      context: context,
      title: 'Quitter le groupe',
      content: 'Vous ne recevrez plus ses messages et devrez être réinvité '
          'pour y revenir.',
      cancelText: 'Annuler',
      confirmText: 'Quitter',
      isDestructive: true,
    );
    if (confirme != true || !context.mounted) return;

    try {
      await ref.read(matrixServiceProvider).leaveRoom(roomId);
      ref.read(matrixStateNotifierProvider.notifier).state++;
      if (context.mounted) context.go('/home');
    } catch (e) {
      if (context.mounted) {
        await showAdaptiveAlert<void>(
          context: context,
          title: 'Impossible de quitter le groupe',
          content: '$e',
        );
      }
    }
  }

  /// Supprime le groupe pour tout le monde.
  ///
  /// Matrix ne détruit pas une room : on renvoie les membres puis on part. Le
  /// dire dans la confirmation, plutôt que de laisser croire à un effacement
  /// des messages côté serveur.
  Future<void> _supprimer(BuildContext context, WidgetRef ref) async {
    final confirme = await showAdaptiveAlert<bool>(
      context: context,
      title: 'Supprimer le groupe',
      content: 'Tous les membres en seront retirés et le groupe disparaîtra '
          'de leur liste. Vous ne pourrez pas revenir en arrière.',
      cancelText: 'Annuler',
      confirmText: 'Supprimer',
      isDestructive: true,
    );
    if (confirme != true || !context.mounted) return;

    // Les membres sont retirés un par un : l'opération dure. Sans témoin,
    // l'écran se vide pendant près d'une minute sans rien dire.
    unawaited(
      showAdaptiveDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog.adaptive(
          content: SizedBox(
            height: 72,
            child: Center(child: CircularProgressIndicator.adaptive()),
          ),
        ),
      ),
    );
    // Navigateur capturé avant l'attente : après, le `context` de l'écran peut
    // avoir disparu, et c'est justement le cas quand la suppression aboutit.
    final navigateur = Navigator.of(context, rootNavigator: true);
    var attente = true;
    void fermerAttente() {
      if (!attente || !navigateur.mounted) return;
      attente = false;
      navigateur.pop();
    }

    try {
      final matrixService = ref.read(matrixServiceProvider);

      // Les médias d'abord, tant qu'on est encore administrateur de la room :
      // la gateway vérifie ce droit, et après le départ il n'existe plus.
      // Best-effort : un échec ici ne doit pas empêcher la suppression.
      final medias = await matrixService.mediasDuGroupe(roomId);
      if (medias.isNotEmpty) {
        try {
          final supprimes = await ref
              .read(botGatewayServiceProvider)
              .deleteRoomMedia(roomId, medias);
          debugPrint('Suppression groupe : $supprimes/${medias.length} médias');
        } catch (e) {
          debugPrint('Suppression groupe : médias non effacés ($e)');
        }
      }

      final restants = await matrixService.supprimerGroupe(roomId);
      fermerAttente();
      ref.read(matrixStateNotifierProvider.notifier).state++;
      if (!context.mounted) return;
      if (restants.isNotEmpty) {
        await showAdaptiveAlert<void>(
          context: context,
          title: 'Groupe quitté, mais pas vidé',
          content: '${restants.length} membre(s) ont les mêmes droits que vous '
              'et sont restés dans le groupe.',
        );
      }
      if (context.mounted) context.go('/home');
    } catch (e) {
      fermerAttente();
      if (context.mounted) {
        await showAdaptiveAlert<void>(
          context: context,
          title: 'Suppression impossible',
          content: '$e',
        );
      }
    }
  }

  /// Exécute une action d'administration puis rafraîchit l'affichage.
  ///
  /// Le `Client` Matrix vit hors du graphe Riverpod : sans l'incrément du
  /// compteur, l'écran garderait la valeur d'avant.
  Future<void> _appliquer(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
    String titreErreur,
  ) async {
    try {
      await action();
      ref.read(matrixStateNotifierProvider.notifier).state++;
    } catch (e) {
      if (context.mounted) {
        await showAdaptiveAlert<void>(
          context: context,
          title: titreErreur,
          content: '$e',
        );
      }
    }
  }
}

/// Petite boîte de saisie adaptative : `showAdaptiveAlert` ne prend qu'un texte.
Future<String?> demanderTexte({
  required BuildContext context,
  required String titre,
  required String valeurInitiale,
  required String placeholder,
  required String valider,
  int lignes = 1,
}) async {
  final controller = TextEditingController(text: valeurInitiale);
  final valide = await showAdaptiveDialog<bool>(
    context: context,
    builder: (context) => AlertDialog.adaptive(
      title: Text(titre),
      content: AdaptiveTextField(
        controller: controller,
        placeholder: placeholder,
        autofocus: true,
        maxLines: lignes,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(valider),
        ),
      ],
    ),
  );
  final texte = controller.text.trim();
  controller.dispose();
  return (valide ?? false) ? texte : null;
}

class _TuileMembre extends ConsumerWidget {
  const _TuileMembre({
    required this.membre,
    required this.estMoi,
    required this.roomId,
  });

  final User membre;
  final bool estMoi;
  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Même source de vérité que partout ailleurs : le nom Supabase prime sur le
    // nom Matrix, qui reste le repli des bots et des comptes distants.
    final contact = ref.watch(contactProfileProvider(membre.id)).value;
    final nom = contact?.name ?? membre.calcDisplayname();
    final supprime = contact?.deleted ?? false;

    return AdaptiveListTile(
      leading: UserAvatar(
        name: nom,
        imageUrl: contact?.avatarUrl,
        size: 40,
        deleted: supprime,
      ),
      title: Text(estMoi ? '$nom (vous)' : nom),
      // Le rôle seulement : le mxid est du bruit dans une liste, il a sa place
      // sur la fiche que cette tuile ouvre.
      subtitle: switch (_role(membre)) {
        final role? => Text(role),
        _ => null,
      },
      onTap: () => _actions(context, ref, nom),
    );
  }

  Future<void> _actions(
    BuildContext context,
    WidgetRef ref,
    String nom,
  ) async {
    await showAdaptiveActionSheet<void>(
      context: context,
      title: nom,
      actions: [
        AdaptiveAction(
          label: 'Voir la fiche',
          onPressed: () =>
              context.push('/user/${Uri.encodeComponent(membre.id)}'),
        ),
        if (!estMoi)
          AdaptiveAction(
            label: 'Envoyer un message privé',
            onPressed: () => _messagePrive(context, ref),
          ),
        if (!estMoi && membre.canChangeUserPowerLevel)
          ..._actionsRole(context, ref, nom),
        if (membre.canKick)
          AdaptiveAction(
            label: 'Retirer du groupe',
            isDestructive: true,
            onPressed: () => _retirer(context, ref, nom),
          ),
      ],
      cancelAction: const AdaptiveAction(label: 'Annuler'),
    );
  }

  bool _estAdmin(User membre) =>
      membre.powerLevel.role == PowerLevelRole.admin ||
      membre.powerLevel.role == PowerLevelRole.owner;

  /// Rôles proposés pour ce membre, selon celui qu'il a déjà.
  ///
  /// Deux paliers plutôt qu'un : modérateur (50) suffit pour aider à tenir le
  /// groupe et reste réversible, alors que nommer quelqu'un administrateur au
  /// même niveau que soi ne se défait plus (Matrix interdit de toucher à un
  /// membre qui n'est pas strictement en dessous de soi).
  List<AdaptiveAction<void>> _actionsRole(
    BuildContext context,
    WidgetRef ref,
    String nom,
  ) {
    final role = membre.powerLevel.role;
    return [
      if (role == PowerLevelRole.user)
        AdaptiveAction(
          label: 'Nommer modérateur',
          onPressed: () => _changerRole(
            context,
            ref,
            nom,
            PowerLevel.defaultModeratorLevel,
          ),
        ),
      if (!_estAdmin(membre))
        AdaptiveAction(
          label: 'Nommer administrateur',
          onPressed: () => _changerRole(
            context,
            ref,
            nom,
            PowerLevel.defaultAdminLevel,
          ),
        ),
      if (role != PowerLevelRole.user)
        AdaptiveAction(
          label: 'Retirer son rôle',
          onPressed: () => _changerRole(
            context,
            ref,
            nom,
            PowerLevel.defaultUserLevel,
          ),
        ),
    ];
  }

  /// Promeut un membre administrateur, ou lui retire ce rôle.
  ///
  /// Matrix interdit de toucher à quelqu'un d'au moins son propre niveau, d'où
  /// `canChangeUserPowerLevel` en garde : c'est le SDK qui connaît la règle.
  Future<void> _changerRole(
    BuildContext context,
    WidgetRef ref,
    String nom,
    int niveau,
  ) async {
    final monNiveau = membre.room.ownPowerLevel;
    final confirme = await showAdaptiveAlert<bool>(
      context: context,
      title: switch (niveau) {
        PowerLevel.defaultAdminLevel => 'Nommer $nom administrateur',
        PowerLevel.defaultModeratorLevel => 'Nommer $nom modérateur',
        _ => 'Retirer son rôle à $nom',
      },
      content: switch (niveau) {
        PowerLevel.defaultAdminLevel => '$nom pourra gérer le groupe et ses '
            'membres.'
            // Sans cet avertissement, on ferait signer un aller sans retour.
            '${niveau >= monNiveau.level ? ' Vous ne pourrez plus revenir en '
                'arrière : ce rôle vaut le vôtre.' : ''}',
        PowerLevel.defaultModeratorLevel =>
          '$nom pourra retirer des messages et des membres.',
        _ => '$nom redeviendra un membre ordinaire du groupe.',
      },
      cancelText: 'Annuler',
      confirmText: niveau == PowerLevel.defaultUserLevel ? 'Retirer' : 'Nommer',
      isDestructive: niveau == PowerLevel.defaultUserLevel,
    );
    if (confirme != true) return;

    try {
      await ref
          .read(matrixServiceProvider)
          .changerNiveauPouvoir(roomId, membre.id, niveau);
      ref.read(matrixStateNotifierProvider.notifier).state++;
    } catch (e) {
      if (context.mounted) {
        await showAdaptiveAlert<void>(
          context: context,
          title: 'Changement de rôle impossible',
          content: '$e',
        );
      }
    }
  }

  Future<void> _messagePrive(BuildContext context, WidgetRef ref) async {
    try {
      // `createDirectChat` rend le fil existant s'il y en a un : toucher deux
      // fois n'ouvre pas deux conversations.
      final id =
          await ref.read(matrixServiceProvider).createDirectChat(membre.id);
      ref.read(matrixStateNotifierProvider.notifier).state++;
      if (context.mounted) context.pushReplacement('/chat/$id');
    } catch (e) {
      if (context.mounted) {
        await showAdaptiveAlert<void>(
          context: context,
          title: 'Conversation impossible',
          content: '$e',
        );
      }
    }
  }

  Future<void> _retirer(
    BuildContext context,
    WidgetRef ref,
    String nom,
  ) async {
    final confirme = await showAdaptiveAlert<bool>(
      context: context,
      title: 'Retirer $nom',
      content: '$nom ne recevra plus les messages du groupe. Vous pourrez '
          "l'inviter à nouveau plus tard.",
      cancelText: 'Annuler',
      confirmText: 'Retirer',
      isDestructive: true,
    );
    if (confirme != true) return;

    try {
      await ref.read(matrixServiceProvider).kickFromRoom(roomId, membre.id);
      ref.read(matrixStateNotifierProvider.notifier).state++;
      ref.invalidate(roomMembersProvider(roomId));
    } catch (e) {
      if (context.mounted) {
        await showAdaptiveAlert<void>(
          context: context,
          title: 'Retrait impossible',
          content: '$e',
        );
      }
    }
  }

  String? _role(User membre) {
    switch (membre.powerLevel.role) {
      case PowerLevelRole.owner:
      case PowerLevelRole.admin:
        return 'Administrateur';
      case PowerLevelRole.moderator:
        return 'Modérateur';
      case PowerLevelRole.user:
        return null;
    }
  }
}
