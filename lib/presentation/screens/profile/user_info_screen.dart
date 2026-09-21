import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/providers/providers.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/common/deleted_account_badge.dart';
import '../../widgets/common/user_avatar.dart';

/// Fiche publique d'une personne, ouverte en touchant son nom dans l'en-tête
/// d'une conversation ou dans la liste des membres d'un groupe.
///
/// Deux sources, dans cet ordre : le profil Supabase (source de vérité des
/// noms, avatars et bios des utilisateurs de l'app), puis le profil Matrix en
/// repli, seul disponible pour un bot ou un compte d'un autre serveur.
class UserInfoScreen extends ConsumerWidget {
  const UserInfoScreen({required this.mxid, super.key});

  final String mxid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matrixService = ref.watch(matrixServiceProvider);
    final client = ref.watch(matrixClientProvider);
    final supabaseId = matrixService.supabaseIdFromMatrixUserId(mxid);

    final profilAsync =
        supabaseId == null ? null : ref.watch(profileProvider(supabaseId));
    final profil = profilAsync?.value;
    // Le mxid dérive bien d'un id Supabase mais la ligne a disparu : compte
    // supprimé. À distinguer du profil pas encore chargé, d'où le `hasValue`.
    final supprime =
        profilAsync != null && profilAsync.hasValue && profil == null;

    final profilMatrix = ref.watch(matrixProfileProvider(mxid)).value;

    final nom = profil?.name ??
        profilMatrix?.displayName ??
        matrixService.getLocalpart(mxid);

    return AdaptiveScaffold(
      title: 'Informations',
      previousPageTitle: 'Retour',
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        children: [
          Center(
            child: UserAvatar(
              name: nom,
              imageUrl: profil?.avatarUrl,
              mxc: profilMatrix?.avatarUrl,
              client: client,
              size: 96,
              deleted: supprime,
            ),
          ),
          const SizedBox(height: 16),
          if (supprime)
            const Center(child: DeletedAccountBadge())
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  nom,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ),
          const SizedBox(height: 24),
          if (profil?.bio != null && profil!.bio!.isNotEmpty)
            _Ligne(titre: 'Bio', valeur: profil.bio!),
          if (profil != null)
            _Ligne(titre: "Nom d'utilisateur", valeur: '@${profil.username}'),
          _Ligne(titre: 'Identifiant Matrix', valeur: mxid),
          if (profil != null)
            _Ligne(
              titre: 'Membre depuis',
              valeur: DateFormat.yMMMM('fr_FR').format(profil.createdAt),
            ),
        ],
      ),
    );
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne({required this.titre, required this.valeur});

  final String titre;
  final String valeur;

  @override
  Widget build(BuildContext context) {
    return AdaptiveListTile(
      title: Text(titre),
      subtitle: Text(valeur),
      // Rien à ouvrir : sans ce trailing, la version iOS afficherait un chevron
      // qui promet une navigation inexistante.
      trailing: const SizedBox.shrink(),
    );
  }
}
