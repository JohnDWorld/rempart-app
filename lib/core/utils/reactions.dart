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

/// Préfixe des règles qui taisent les réactions de mes bots.
const _prefixeRegleBot = 'fr.rempart.reactions_de_mon_bot.';

/// Identifiant de la règle qui tait les réactions de [mxid].
///
/// Sans « @ » ni « : » : un identifiant qui voyage dans l'adresse de la
/// requête doit revenir de Synapse tel qu'il est parti, encodé ou non.
String regleBot(String mxid) =>
    _prefixeRegleBot + mxid.replaceAll(RegExp('[^a-z0-9._-]'), '_');

/// Une réaction de ce bot ne notifie pas (aucune action).
///
/// Un agent réagit 👀 à chaque message pour dire qu'il l'a vu : avec la règle
/// de réaction, chacun sonnait, au téléphone, à la montre et dans la voiture
/// (relevé le 2026-11-25). Ce qu'on attend de lui, c'est sa réponse. C'est
/// le serveur qui les tait, et non l'application : un push urgent qui
/// n'affiche rien pousse Google à rétrograder ceux de Rempart, vrais messages
/// compris.
Map<String, Object?> corpsRegleBot(String mxid) => {
      'conditions': [
        {'kind': 'event_match', 'key': 'type', 'pattern': 'm.reaction'},
        {'kind': 'event_match', 'key': 'sender', 'pattern': mxid},
      ],
      'actions': <Object>[],
    };

/// Ce qu'il reste à faire pour que les réactions de [bots] se taisent.
///
/// [override] : les règles `override` du compte, dans l'ordre où Synapse les
/// évalue. Une règle de bot ne tait rien si elle passe APRÈS [regleReactions],
/// qui aurait déjà décidé de notifier. Or une règle posée sans position monte
/// en tête : reposer la règle de réaction oblige donc à replacer les bots.
/// [bots] à `null` (la passerelle n'a pas encore répondu) : on ne touche à
/// aucune règle de bot.
({bool reposerReactions, List<String> placer, List<String> retirer})
    planReglesReactions({
  required List<String> override,
  required Set<String>? bots,
}) {
  final iReactions = override.indexOf(regleReactions);
  final reposer = iReactions < 0;
  bool enPlace(String bot) {
    final i = override.indexOf(regleBot(bot));
    return i >= 0 && i < iReactions;
  }

  final attendues = {for (final bot in bots ?? const <String>{}) regleBot(bot)};
  return (
    reposerReactions: reposer,
    placer: [
      for (final bot in bots ?? const <String>{})
        if (reposer || !enPlace(bot)) bot,
    ],
    retirer: [
      if (bots != null)
        for (final id in override)
          if (id.startsWith(_prefixeRegleBot) && !attendues.contains(id)) id,
    ],
  );
}
