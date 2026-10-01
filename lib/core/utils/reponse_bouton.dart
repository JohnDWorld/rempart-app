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
