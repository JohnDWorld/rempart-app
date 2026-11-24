/// Prépare un message pour la synthèse vocale.
///
/// Android refuse en bloc un texte de plus de 4 000 caractères
/// (`TextToSpeech.getMaxSpeechInputLength`), et Chrome coupe court une longue
/// lecture : le texte part donc en morceaux, coupés entre deux phrases, sinon
/// entre deux mots, à défaut au milieu. Une adresse se lit « lien » : épelée,
/// elle durerait plus longtemps que le message.
List<String> morceauxALire(String texte, {int max = 3000}) {
  final propre = texte
      .replaceAll(RegExp(r'(https?://|www\.)\S*[^\s.,;:!?)]'), 'lien')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final morceaux = <String>[];
  var reste = propre;
  while (reste.length > max) {
    final tete = reste.substring(0, max + 1);
    // Fin de phrase la plus lointaine, sinon dernier espace.
    var coupe = tete.lastIndexOf(RegExp('[.!?…] '));
    coupe = coupe > 0 ? coupe + 1 : tete.lastIndexOf(' ');
    if (coupe <= 0) coupe = max;
    morceaux.add(reste.substring(0, coupe).trim());
    reste = reste.substring(coupe).trim();
  }
  if (reste.isNotEmpty) morceaux.add(reste);
  return morceaux;
}
