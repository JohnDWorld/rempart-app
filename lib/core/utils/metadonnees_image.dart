import 'dart:typed_data';

/// La photo sans ce qu'elle dit d'elle-même : position, appareil, heure,
/// logiciel, miniature embarquée.
///
/// Jusqu'au 2026-11-06, une photo ne les perdait que par accident, quand la
/// compression la réencodait : en HD, sous 300 Ko ou en PNG, elle partait avec
/// sa position GPS. Le tri se fait sans réencoder, en ne recopiant que les
/// segments du fichier qui font l'image : une photo HD reste à l'octet près.
///
/// Deux choses restent, parce que l'image en dépend : l'orientation (sans
/// elle, une photo prise debout s'affiche couchée) et le profil de couleur
/// (sans lui, celles des iPhone récents ternissent).
///
/// Null si le format n'est ni JPEG ni PNG, ou si le fichier est illisible :
/// mieux vaut le dire que recopier à moitié.
Uint8List? sansMetadonnees(Uint8List octets) {
  if (octets.length > 3 &&
      octets[0] == 0xFF &&
      octets[1] == 0xD8 &&
      octets[2] == 0xFF) {
    return _jpeg(octets);
  }
  if (octets.length > 8 &&
      _signaturePng.indexed.every((e) => octets[e.$1] == e.$2)) {
    return _png(octets);
  }
  return null;
}

/// Un JPEG ne garde que ses tables, son en-tête et ses passes, plus le
/// profil de couleur (APP2 `ICC_PROFILE`) et le segment Adobe (APP14, qui
/// dit comment lire les couleurs). Partent : Exif et XMP (APP1), IPTC
/// (APP13), MPF (APP2, qui annonce une seconde image), JFIF et sa miniature
/// (APP0), commentaires, et tout ce qui suit la fin de l'image (la vidéo
/// d'une photo animée, la carte de gain d'une photo HDR).
Uint8List? _jpeg(Uint8List o) {
  final gardes = BytesBuilder(copy: false);
  var orientation = 1;
  var i = 2;
  while (i + 1 < o.length) {
    if (o[i] != 0xFF) return null;
    final marqueur = o[i + 1];
    if (marqueur == 0xFF) {
      i++; // octet de remplissage
      continue;
    }
    if (marqueur == 0xD9) return _assembler(gardes, orientation);
    if (i + 3 >= o.length) return null;
    final fin = i + 2 + ((o[i + 2] << 8) | o[i + 3]);
    if (fin > o.length || fin < i + 4) return null;
    final segment = Uint8List.sublistView(o, i, fin);

    if (marqueur == 0xE1 && _commencePar(segment, _exif)) {
      orientation = _orientation(segment) ?? orientation;
    } else if (_garder(marqueur, segment)) {
      gardes.add(segment);
    }
    i = fin;

    if (marqueur == 0xDA) {
      // Les données d'une passe courent jusqu'au prochain marqueur, qui n'est
      // ni un octet échappé (FF 00) ni une reprise (FF D0 à D7).
      final debut = i;
      while (i + 1 < o.length &&
          !(o[i] == 0xFF &&
              o[i + 1] != 0x00 &&
              o[i + 1] != 0xFF &&
              (o[i + 1] < 0xD0 || o[i + 1] > 0xD7))) {
        i++;
      }
      if (i + 1 >= o.length) return null;
      gardes.add(Uint8List.sublistView(o, debut, i));
    }
  }
  return null;
}

bool _garder(int marqueur, Uint8List segment) {
  if (marqueur == 0xFE) return false; // commentaire
  if (marqueur < 0xE0 || marqueur > 0xEF) return true; // ce qui fait l'image
  return (marqueur == 0xE2 && _commencePar(segment, _icc)) ||
      (marqueur == 0xEE && _commencePar(segment, _adobe));
}

Uint8List _assembler(BytesBuilder gardes, int orientation) {
  final sortie = BytesBuilder(copy: false)..add(const [0xFF, 0xD8]);
  if (orientation != 1) {
    sortie.add([
      0xFF, 0xE1, 0, 34, // APP1, 34 octets
      ..._exif.skip(4),
      0x4D, 0x4D, 0x00, 0x2A, 0, 0, 0, 8, // TIFF grand-boutiste, IFD0 en 8
      0, 1, // une seule entrée
      0x01, 0x12, 0, 3, 0, 0, 0, 1, 0, orientation, 0, 0, // Orientation
      0, 0, 0, 0, // pas d'IFD suivant
    ]);
  }
  return (sortie
        ..add(gardes.takeBytes())
        ..add(const [0xFF, 0xD9]))
      .takeBytes();
}

/// L'orientation (étiquette 0x0112) de l'IFD0, dans l'un ou l'autre ordre
/// d'octets. Null si l'Exif ne la porte pas ou ne se lit pas.
int? _orientation(Uint8List segment) {
  const tiff = 10; // marqueur, longueur, « Exif\0\0 »
  if (segment.length < tiff + 8) return null;
  final d = ByteData.sublistView(segment, tiff);
  final ordre = switch ((segment[tiff], segment[tiff + 1])) {
    (0x49, 0x49) => Endian.little,
    (0x4D, 0x4D) => Endian.big,
    _ => null,
  };
  if (ordre == null) return null;
  final ifd = d.getUint32(4, ordre);
  if (ifd + 2 > d.lengthInBytes) return null;
  final nombre = d.getUint16(ifd, ordre);
  for (var k = 0; k < nombre; k++) {
    final e = ifd + 2 + 12 * k;
    if (e + 12 > d.lengthInBytes) return null;
    if (d.getUint16(e, ordre) != 0x0112) continue;
    final valeur = d.getUint16(e + 8, ordre);
    return valeur >= 1 && valeur <= 8 ? valeur : null;
  }
  return null;
}

/// Un PNG garde les morceaux qui font l'image (les critiques, et ceux qui
/// règlent couleurs, transparence et animation), et perd les autres : Exif,
/// textes (auteur, logiciel, commentaire), heure. Les morceaux gardés sont
/// recopiés tels quels, sommes de contrôle comprises.
Uint8List? _png(Uint8List o) {
  final sortie = BytesBuilder(copy: false)..add(Uint8List.sublistView(o, 0, 8));
  final d = ByteData.sublistView(o);
  var i = 8;
  while (i + 12 <= o.length) {
    final fin = i + 12 + d.getUint32(i);
    if (fin > o.length) return null;
    final type = String.fromCharCodes(o, i + 4, i + 8);
    // Majuscule en tête : critique, le décodeur en a besoin.
    if (o[i + 4] < 0x61 || _pngGardes.contains(type)) {
      sortie.add(Uint8List.sublistView(o, i, fin));
    }
    if (type == 'IEND') return sortie.takeBytes();
    i = fin;
  }
  return null;
}

const _pngGardes = {
  'tRNS', 'gAMA', 'cHRM', 'sRGB', 'iCCP', 'sBIT', 'cICP', 'mDCV', 'cLLI', //
  'bKGD', 'pHYs', 'acTL', 'fcTL', 'fdAT',
};

const _signaturePng = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

// Les préfixes comptent le marqueur et la longueur (4 octets).
const _exif = [0, 0, 0, 0, 0x45, 0x78, 0x69, 0x66, 0, 0]; // « Exif\0\0 »
const _icc = [0, 0, 0, 0, ..._iccTexte, 0]; // « ICC_PROFILE\0 »
const _iccTexte = [
  0x49,
  0x43,
  0x43,
  0x5F,
  0x50,
  0x52,
  0x4F,
  0x46,
  0x49,
  0x4C,
  0x45
];
const _adobe = [0, 0, 0, 0, 0x41, 0x64, 0x6F, 0x62, 0x65]; // « Adobe »

bool _commencePar(Uint8List segment, List<int> prefixe) {
  if (segment.length < prefixe.length) return false;
  for (var k = 4; k < prefixe.length; k++) {
    if (segment[k] != prefixe[k]) return false;
  }
  return true;
}
