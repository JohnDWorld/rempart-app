import 'package:matrix/matrix.dart' as matrix;

/// Le message envoyé quand on appuie sur un bouton sous un message de bot.
///
/// Le corps porte la valeur, seule chose que lisent l'agent et les autres
/// clients ; le libellé voyage à côté pour que Rempart l'affiche à sa place.
/// `fr.rempart.reponse_a` désigne le message qui portait les boutons : la
/// passerelle y lit à quelle question on répond. Sans lui, deux validations
/// en attente dans le même salon avec les mêmes boutons se confondraient, et
/// la réponse pourrait valider la mauvaise action.
Map<String, Object> contenuReponseBouton({
  required String valeur,
  required String libelle,
  String? questionId,
}) =>
    {
      'msgtype': 'm.text',
      'body': valeur,
      'fr.rempart.libelle_bouton': libelle,
      if (questionId != null) 'fr.rempart.reponse_a': questionId,
    };

/// Ce que j'ai déjà répondu aux boutons de ce fil : l'identifiant du message
/// qui portait les boutons, et le libellé choisi.
///
/// Les boutons d'une question à laquelle on a répondu restaient en place, et
/// dans une suite de messages à boutons on ne savait plus lesquels on avait
/// touchés (relevé le 2026-11-25). Lu dans le fil plutôt que retenu au moment
/// de l'appui : la réponse vaut aussi sur un autre appareil et après un
/// redémarrage. Seules les miennes comptent, un autre membre d'un groupe
/// pouvant avoir sa propre réponse à donner ; et une réponse en échec laisse
/// les boutons, pour réessayer.
Map<String, String> reponsesAuxBoutons(
  Iterable<matrix.Event> events,
  String? moi,
) {
  final reponses = <String, String>{};
  if (moi == null) return reponses;
  for (final e in events) {
    if (e.senderId != moi || e.status.isError) continue;
    final question = e.content['fr.rempart.reponse_a'];
    if (question is! String) continue;
    final libelle = e.content['fr.rempart.libelle_bouton'];
    reponses.putIfAbsent(question, () => libelle is String ? libelle : e.body);
  }
  return reponses;
}
