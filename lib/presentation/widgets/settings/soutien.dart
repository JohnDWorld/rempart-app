import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';

/// Ouvre la page de soutien dans le navigateur.
///
/// Le paiement ne se fait jamais dans l'application, et ce n'est pas une
/// facilité : Apple traite un « soutenez le développeur » encaissé dans
/// l'application comme un achat de contenu numérique, ce qui impose l'achat
/// intégré et sa commission. Sur le web, la totalité arrive.
///
/// L'ouverture est déléguée au navigateur (`externalApplication`) plutôt qu'à
/// une vue intégrée : une page de paiement doit montrer sa barre d'adresse et
/// son cadenas, sans quoi l'utilisateur n'a aucun moyen de vérifier à qui il
/// donne son numéro de carte.
Future<void> ouvrirPageDeSoutien(BuildContext context) async {
  final uri = Uri.parse(AppConstants.donUrl);
  var ouvert = false;
  try {
    ouvert = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    ouvert = false;
  }
  if (ouvert || !context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    const SnackBar(content: Text("Impossible d'ouvrir la page de soutien.")),
  );
}
