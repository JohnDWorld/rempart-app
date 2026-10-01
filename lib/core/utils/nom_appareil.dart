/// Le nom que chaque appareil porte sur le compte, et ce que l'écran
/// « Appareils connectés » en tire.
///
/// Le serveur ne dit au client ni le navigateur ni le système d'une session :
/// seul son nom voyage. Jusqu'au 2026-10-01, tous s'appelaient « Rempart
/// Messenger », et la liste ne savait pas distinguer un navigateur d'un
/// téléphone. Chaque appareil se nomme donc d'après ce qu'il est, sous une
/// forme que l'écran relit (et qu'un autre client Matrix affiche telle
/// quelle) : « Rempart · Android », « Rempart · Opera (Linux) ».
library;

const _prefixe = 'Rempart · ';

/// Le navigateur et le système, lus dans la signature du navigateur.
///
/// L'ordre compte : Opera et Edge se déclarent aussi « Chrome », Chrome se
/// déclare aussi « Safari », et Android se déclare aussi « Linux ».
(String, String?) lireUserAgent(String ua) {
  final navigateur = ua.contains('OPR/') || ua.contains('Opera')
      ? 'Opera'
      : ua.contains('Edg/') || ua.contains('EdgA/') || ua.contains('EdgiOS/')
          ? 'Edge'
          : ua.contains('Firefox/') || ua.contains('FxiOS/')
              ? 'Firefox'
              : ua.contains('Chrome/') || ua.contains('CriOS/')
                  ? 'Chrome'
                  : ua.contains('Safari/')
                      ? 'Safari'
                      : 'Navigateur';
  final systeme = ua.contains('Android')
      ? 'Android'
      : ua.contains('iPhone') || ua.contains('iPad')
          ? 'iOS'
          : ua.contains('Windows')
              ? 'Windows'
              : ua.contains('CrOS')
                  ? 'ChromeOS'
                  : ua.contains('Mac OS X')
                      ? 'macOS'
                      : ua.contains('Linux')
                          ? 'Linux'
                          : null;
  return (navigateur, systeme);
}

/// Le nom de cet appareil : l'application mobile par son système, la version
/// web par son navigateur.
String nomAppareil({required bool android, required bool ios, String? userAgent}) {
  if (android) return '${_prefixe}Android';
  if (ios) return '${_prefixe}iOS';
  final (navigateur, systeme) = lireUserAgent(userAgent ?? '');
  return systeme == null
      ? '$_prefixe$navigateur'
      : '$_prefixe$navigateur ($systeme)';
}

enum GenreAppareil { telephone, navigateur, inconnu }

/// Ce que la liste affiche d'un appareil.
typedef DescriptionAppareil = ({
  GenreAppareil genre,
  String titre,
  String? pastille,
});

/// Relit un nom posé par [nomAppareil]. Un autre nom (l'ancien « Rempart
/// Messenger », un autre client Matrix) s'affiche tel quel, sans pastille.
DescriptionAppareil decrireAppareil(String? nom) {
  if (nom == null || nom.isEmpty) {
    return (
      genre: GenreAppareil.inconnu,
      titre: 'Appareil sans nom',
      pastille: null,
    );
  }
  if (!nom.startsWith(_prefixe)) {
    return (genre: GenreAppareil.inconnu, titre: nom, pastille: null);
  }
  final reste = nom.substring(_prefixe.length);
  if (reste == 'Android' || reste == 'iOS') {
    return (
      genre: GenreAppareil.telephone,
      titre: 'Application $reste',
      pastille: reste,
    );
  }
  final morceaux = RegExp(r'^(.+?)(?: \((.+)\))?$').firstMatch(reste)!;
  final navigateur = morceaux.group(1)!;
  final systeme = morceaux.group(2);
  return (
    genre: GenreAppareil.navigateur,
    titre: systeme == null ? navigateur : '$navigateur sur $systeme',
    pastille: navigateur,
  );
}
