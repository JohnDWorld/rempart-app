/// Un message ressemble-t-il à un secret qu'on ne veut pas voir s'afficher
/// sans l'avoir demandé : code à usage unique, mot de passe transmis à la main ?
///
/// Volontairement étroit. Une heuristique large masquerait des messages
/// ordinaires, ce qui gêne autant qu'une fuite : on ne retient donc que deux
/// formes nettes, et on laisse passer le reste.
///
/// La détection tourne **chez le destinataire** : dans une conversation
/// chiffrée le serveur ne voit rien, et il n'est pas question que ça change
/// pour cette fonctionnalité.
library;

/// Mots qui annoncent un secret dans la phrase qui l'entoure.
///
/// Sans accent et en minuscules : le texte est normalisé avant comparaison,
/// pour que « vérification » et « verification » se valent.
const _annonces = <String>[
  'code',
  'otp',
  'pin',
  'mot de passe',
  'motdepasse',
  'mdp',
  'password',
  'passphrase',
  'identifiant',
  'secret',
  'verification',
  'confirmation',
  '2fa',
  'totp',
  'authentification',
];

/// Les annonces, cherchées comme des **mots** et non des morceaux de mots.
///
/// `contains` les cherchait n'importe où, et « code » se trouvait alors dans
/// « openai-codex », « décodeur » ou « codebase ». Un message d'agent annonçant
/// son modèle (« Provider: openai-codex », « Model: gpt-5.6-sol ») se voyait
/// ainsi masqué : une annonce par accident, un numéro de version pris pour un
/// jeton, et le message disparaissait.
final _motAnnonce = RegExp(
  '(?<![a-z0-9])(?:${_annonces.map(RegExp.escape).join('|')})(?![a-z0-9])',
);

/// Forme d'un message qui ne serait qu'un code : des chiffres, des espaces ou
/// des tirets pour les grouper, et rien d'autre qu'une ponctuation légère.
final _formeCodeSeul = RegExp(r'^[\s]*[\d\s-]{5,12}[\s.!]*$');

/// [texte] n'est-il qu'un code à usage unique ?
///
/// Cinq chiffres au minimum, et non quatre : « 2026 » est une année, et une
/// conversation en est pleine. Huit au maximum : au-delà on tombe sur des
/// numéros de téléphone ou de commande, qui n'ont rien de secret.
bool _estUnCodeSeul(String texte) {
  if (!_formeCodeSeul.hasMatch(texte)) return false;
  final chiffres = texte.replaceAll(RegExp(r'\D'), '').length;
  return chiffres >= 5 && chiffres <= 8;
}

/// Suite de 4 à 10 chiffres isolée dans la phrase (un code annoncé).
final _suiteDeChiffres = RegExp(r'(?<!\d)\d{4,10}(?!\d)');

/// Jeton d'au moins 6 caractères mêlant lettre et chiffre : la forme d'un mot
/// de passe tapé à la main.
final _jetonMixte = RegExp(r'(?:^|\s)(?=\S*[a-z])(?=\S*\d)\S{6,}(?:\s|$)');

/// Vrai si [texte] ressemble à un secret.
bool ressembleAUnSecret(String texte) {
  final brut = texte.trim();
  if (brut.isEmpty || brut.length > 300) return false;

  if (_estUnCodeSeul(brut)) return true;

  final normalise = _sansAccents(brut.toLowerCase());
  if (!_motAnnonce.hasMatch(normalise)) return false;

  return _suiteDeChiffres.hasMatch(normalise) ||
      _jetonMixte.hasMatch(normalise);
}

/// Réduit les accents français, pour que la recherche de mots-clés n'ait pas à
/// lister chaque graphie.
String _sansAccents(String texte) {
  const equivalences = {
    'à': 'a', 'â': 'a', 'ä': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'î': 'i', 'ï': 'i',
    'ô': 'o', 'ö': 'o',
    'ù': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c',
  };
  final tampon = StringBuffer();
  for (final caractere in texte.split('')) {
    tampon.write(equivalences[caractere] ?? caractere);
  }
  return tampon.toString();
}
