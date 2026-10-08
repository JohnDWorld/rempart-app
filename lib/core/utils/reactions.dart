/// Les réactions posées sous un message, regroupées par symbole.
class ReactionGroupee {
  ReactionGroupee(this.symbole);

  final String symbole;

  /// Qui a réagi ainsi (mxid), dans l'ordre des réactions : la feuille « qui a
  /// réagi » les nomme, la pastille n'en montre que le nombre.
  final List<String> expediteurs = [];

  int get nombre => expediteurs.length;

  /// Vrai si l'on fait partie de ceux qui ont réagi ainsi : la pastille se
  /// distingue alors, et la feuille propose de retirer sa réaction.
  bool parMoi = false;
}

/// Regroupe les réactions d'un message par symbole, dans l'ordre d'apparition.
///
/// Une réaction retirée reste dans la timeline sous forme d'événement effacé :
/// elle ne compte pas. La même personne avec le même symbole ne compte qu'une
/// fois, quel que soit le client qui l'aurait envoyée deux fois.
List<ReactionGroupee> regrouperReactions(
  Iterable<({String expediteur, String? symbole, bool retiree})> reactions,
  String? moi,
) {
  final parSymbole = <String, ReactionGroupee>{};
  for (final reaction in reactions) {
    final symbole = reaction.symbole;
    if (reaction.retiree || symbole == null || symbole.isEmpty) continue;
    final groupe = parSymbole[symbole] ??= ReactionGroupee(symbole);
    if (groupe.expediteurs.contains(reaction.expediteur)) continue;
    groupe.expediteurs.add(reaction.expediteur);
    if (reaction.expediteur == moi) groupe.parMoi = true;
  }
  return parSymbole.values.toList();
}

/// Identifiant de la règle de push qui fait notifier les réactions à mes
/// messages (voir `MatrixService.activerNotificationsDeReaction`).
const regleReactions = 'fr.rempart.reactions_a_mes_messages';

/// Corps de cette règle : une réaction (`m.reaction`) dont le message visé
/// (`m.annotation`) a été envoyé par [moi].
///
/// La seconde condition est celle de MSC3664 (`msc3664_enabled` côté Synapse) :
/// une règle sur le seul type compterait aussi comme non lues toutes les
/// réactions que les autres s'échangent dans un groupe. Le son n'est pas
/// décoratif : sans lui, Synapse pousse un événement en clair en priorité
/// basse, qu'Android retarde jusqu'à l'ouverture de l'application.
Map<String, Object?> corpsRegleReactions(String moi) => {
      'conditions': [
        {'kind': 'event_match', 'key': 'type', 'pattern': 'm.reaction'},
        {
          'kind': 'im.nheko.msc3664.related_event_match',
          'rel_type': 'm.annotation',
          'key': 'sender',
          'pattern': moi,
        },
      ],
      'actions': [
        'notify',
        {'set_tweak': 'sound', 'value': 'default'},
      ],
    };
