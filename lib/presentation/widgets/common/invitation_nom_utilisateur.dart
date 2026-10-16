import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/nom_utilisateur.dart';
import '../../../data/providers/providers.dart';
import '../adaptive/adaptive.dart';

const _cleDejaPropose = 'invitation_nom_utilisateur_vue';

/// Propose, une seule fois, de quitter un nom d'utilisateur tiré de l'adresse.
///
/// Avant le 2026-10-15, la base prenait le début de l'adresse e-mail comme
/// nom d'utilisateur, et il s'affichait à quiconque trouvait le profil. Ces
/// comptes gardent leur nom (rien ne change sans leur titulaire) ; on leur
/// propose d'en choisir un, puis on n'en parle plus.
Future<void> inviterAChoisirSonNom(BuildContext context) async {
  final email = Supabase.instance.client.auth.currentUser?.email;
  if (email == null) return;
  final conteneur = ProviderScope.containerOf(context, listen: false);
  final routeur = GoRouter.of(context);
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_cleDejaPropose) ?? false) return;
    final profil = await conteneur.read(currentProfileProvider.future);
    if (profil == null || !nomTireDeLAdresse(profil.username, email)) return;
    if (!context.mounted) return;
    await prefs.setBool(_cleDejaPropose, true);
    if (!context.mounted) return;

    final choisir = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => DialogueAdaptatif(
        title: const Text("Choisissez votre nom d'utilisateur"),
        content: Text(
          'Le vôtre, @${profil.username}, reprend le début de votre adresse '
          "e-mail, et s'affiche à qui vous trouve dans Rempart. Un nom choisi "
          "permet de vous trouver tout en gardant l'adresse pour vous.",
        ),
        actions: [
          ActionDialogue(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Garder'),
          ),
          ActionDialogue(
            principale: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Choisir'),
          ),
        ],
      ),
    );
    if (choisir ?? false) unawaited(routeur.push('/profil/modifier'));
  } catch (e) {
    // Profil illisible (réseau) : on proposera à la prochaine ouverture.
    debugPrint('Invitation nom d’utilisateur : $e');
  }
}
