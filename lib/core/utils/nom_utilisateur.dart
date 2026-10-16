/// Les noms d'utilisateur (`@marie.d`) : ce qui distingue deux homonymes.
///
/// Le nom affiché (« Marie Dupont ») n'est pas unique et ne peut pas l'être ;
/// le nom d'utilisateur l'est, sans tenir compte de la casse. Il se choisit à
/// l'inscription et se change dans le profil. Il était tiré de l'adresse
/// e-mail jusqu'au 2026-10-15, ce qui en montrait le début à quiconque
/// trouvait le profil.
///
/// Les règles sont celles de la base (`nom_utilisateur_refuse`, migration
/// `20261015120000_noms_utilisateur.sql`), qui reste seule juge : ce reflet
/// sert à répondre sous le champ sans attendre le réseau. Les deux changent
/// ensemble, et `test/nom_utilisateur_test.dart` rejoue les cas essayés sur
/// la base.
library;

const longueurMinNomUtilisateur = 3;
const longueurMaxNomUtilisateur = 30;

final _caracteresPermis = RegExp(r'^[a-z0-9._]+$');
final _forme = RegExp(r'^[a-z](?:[a-z0-9]|[._](?=[a-z0-9]))+$');

/// Ce qui se ferait passer pour Rempart, pour un bot (les bots finissent par
/// `bot`, convention Telegram) ou pour un identifiant Matrix (`u_<uuid>`).
final _motifReserve = RegExp(r'^(rempart|u_)|bot$');
const _reserves = {
  'admin', 'administrateur', 'administrator', 'moderateur', 'moderation',
  'moderator', 'support', 'aide', 'help', 'contact', 'securite', 'security',
  'officiel', 'official', 'staff', 'equipe', 'team', 'systeme', 'system',
  'root', 'noreply',
};

/// La saisie telle que la base l'enregistre : minuscules, sans espace ni `@`
/// autour.
String normaliserNomUtilisateur(String saisie) =>
    saisie.replaceAll(RegExp(r'^[\s@]+|[\s@]+$'), '').toLowerCase();

/// Ce qui empêche [nom] (normalisé) de servir, ou null s'il est permis.
String? problemeNomUtilisateur(String nom) {
  if (nom.length < longueurMinNomUtilisateur ||
      nom.length > longueurMaxNomUtilisateur) {
    return 'Entre $longueurMinNomUtilisateur et $longueurMaxNomUtilisateur '
        'caractères';
  }
  if (!_caracteresPermis.hasMatch(nom)) {
    return 'Lettres sans accent, chiffres, point et tiret bas seulement';
  }
  if (!RegExp('^[a-z]').hasMatch(nom)) return 'Commencez par une lettre';
  if (!_forme.hasMatch(nom)) {
    return 'Ni point ni tiret bas à la fin, ni deux à la suite';
  }
  if (_motifReserve.hasMatch(nom) || _reserves.contains(nom)) {
    return 'Ce nom est réservé';
  }
  return null;
}

/// Le message d'un refus rendu par la base ([raison] : `pris`, ou l'une des
/// règles).
String messageRefusNomUtilisateur(String raison, String nom) =>
    raison == 'pris'
        ? 'Ce nom est déjà pris'
        : problemeNomUtilisateur(nom) ?? "Ce nom n'est pas permis";

/// Vrai si [nom] (normalisé) peut désigner un compte existant.
///
/// Plus large que les règles : les noms d'avant le 2026-10-15, tirés des
/// adresses, n'y obéissent pas tous (`jean-dupont`, `1marie`), et leurs
/// titulaires doivent rester trouvables. La recherche est exacte, cette
/// largeur ne permet donc de parcourir personne.
bool estUnNomCherchable(String nom) =>
    RegExp(r'^[a-z0-9._+-]{1,64}$').hasMatch(nom);

/// Vrai si [nom] est la partie locale de [email] : un nom d'avant le
/// 2026-10-15, que la base tirait de l'adresse, et qui en montrait donc le
/// début à quiconque trouvait le profil.
bool nomTireDeLAdresse(String nom, String email) =>
    nom.toLowerCase() == email.split('@').first.toLowerCase();

/// Un nom d'utilisateur proposé d'après le nom affiché, que l'on garde ou
/// que l'on change : « Hélène Dupont » donne `helene.dupont`. Vide si rien
/// d'utilisable n'en sort.
String suggestionNomUtilisateur(String nomAffiche) {
  var nom = _sansAccents(nomAffiche.toLowerCase())
      .replaceAll(RegExp(r"[\s'’-]+"), '.')
      .replaceAll(RegExp('[^a-z0-9._]'), '')
      .replaceAll(RegExp('[._]{2,}'), '.')
      .replaceFirst(RegExp('^[^a-z]+'), '');
  if (nom.length > longueurMaxNomUtilisateur) {
    nom = nom.substring(0, longueurMaxNomUtilisateur);
  }
  return nom.replaceFirst(RegExp(r'[._]+$'), '');
}

const _accents = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'å': 'a', 'ç': 'c',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'î': 'i', 'ï': 'i', 'í': 'i',
  'ì': 'i', 'ô': 'o', 'ö': 'o', 'ó': 'o', 'ò': 'o', 'õ': 'o', 'ù': 'u',
  'û': 'u', 'ü': 'u', 'ú': 'u', 'ÿ': 'y', 'ý': 'y', 'ñ': 'n', 'œ': 'oe',
  'æ': 'ae',
};

String _sansAccents(String texte) =>
    texte.split('').map((c) => _accents[c] ?? c).join();

/// L'adresse des liens de contact : la version web de Rempart, qui ouvre le
/// contact dans un navigateur, et qu'Android confie à l'application quand
/// elle est installée (lien d'application vérifié, voir
/// `web/.well-known/assetlinks.json`).
const _hoteLienContact = 'app.rempart-messenger.fr';

/// Le lien qui mène à [nom] : celui du code QR et de « Partager mon lien ».
String lienContact(String nom) =>
    Uri.https(_hoteLienContact, '/contact/$nom').toString();

/// Le nom porté par un lien de contact Rempart, ou null si [texte] n'en est
/// pas un (un autre QR, une autre adresse).
String? nomDepuisLienContact(String texte) {
  final uri = Uri.tryParse(texte.trim());
  if (uri == null || uri.scheme != 'https' || uri.host != _hoteLienContact) {
    return null;
  }
  final segments = uri.pathSegments;
  if (segments.length != 2 || segments.first != 'contact') return null;
  final nom = normaliserNomUtilisateur(segments[1]);
  return estUnNomCherchable(nom) ? nom : null;
}
