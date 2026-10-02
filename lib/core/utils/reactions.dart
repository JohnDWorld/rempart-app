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
