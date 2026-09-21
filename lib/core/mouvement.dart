import 'package:flutter/widgets.dart';

/// Vrai quand l'utilisateur a demandé à son système moins de mouvement.
///
/// iOS (« Réduire les animations ») et Android (« Supprimer les animations »)
/// le signalent tous deux à Flutter par `disableAnimations`. Rien dans
/// Rempart ne l'écoutait : la barre d'envoi qui se transforme, le glisser
/// pour répondre, les onglets et le défilement vers un message cité bougeaient
/// quand même, alors que pour certains le mouvement donne la nausée.
bool animationsReduites(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context);

/// [normale], ou zéro si les animations sont réduites.
///
/// Zéro et non une durée raccourcie : c'est la coupe franche que demandent
/// les consignes des deux systèmes. Le changement d'état reste, et reste
/// lisible ; seul le trajet disparaît.
Duration dureeAnimation(BuildContext context, Duration normale) =>
    animationsReduites(context) ? Duration.zero : normale;
