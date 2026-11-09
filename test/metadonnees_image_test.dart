import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/core/utils/metadonnees_image.dart';

/// Ce qu'une photo emporte d'elle-même, et ce qu'elle doit garder.
///
/// Une photo de téléphone porte la position où elle a été prise, l'appareil,
/// l'heure, parfois une miniature d'avant le recadrage. Rien de cela ne doit
/// partir. L'orientation et le profil de couleur, eux, restent : sans le
/// premier la photo pivote, sans le second ses couleurs ternissent.
void main() {
  group('JPEG', () {
    test("retire la position, l'appareil, le XMP, l'IPTC et le commentaire",
        () {
      final sortie = sansMetadonnees(_jpeg(orientation: 6))!;
      final texte = latin1.decode(sortie);
      expect(texte, isNot(contains('Pixel 8')));
      expect(texte, isNot(contains('GPS48')));
      expect(texte, isNot(contains('ns.adobe.com/xap')));
      expect(texte, isNot(contains('Photoshop 3.0')));
      expect(texte, isNot(contains('Pris chez moi')));
      expect(texte, isNot(contains('MINIATURE')));
    });

    test("garde l'orientation, seule, dans un Exif minimal", () {
      final sortie = sansMetadonnees(_jpeg(orientation: 6))!;
      expect(sortie.sublist(0, 2), [0xFF, 0xD8]);
      expect(
          sortie.sublist(2, 2 + _exifOrientation6.length), _exifOrientation6);
    });

    test("lit l'orientation dans les deux ordres d'octets", () {
      final sortie =
          sansMetadonnees(_jpeg(orientation: 6, grandBoutiste: true))!;
      expect(
          sortie.sublist(2, 2 + _exifOrientation6.length), _exifOrientation6);
    });

    test("une photo droite n'a plus d'Exif du tout", () {
      final sortie = sansMetadonnees(_jpeg(orientation: 1))!;
      expect(latin1.decode(sortie), isNot(contains('Exif')));
    });

    test('garde le profil de couleur et le segment Adobe, pas le MPF', () {
      final texte = latin1.decode(sansMetadonnees(_jpeg(orientation: 1))!);
      expect(texte, contains('ICC_PROFILE'));
      expect(texte, contains('Adobe'));
      expect(texte, isNot(contains('MPF')));
    });

    test("l'image elle-même ne change pas d'un octet", () {
      final sortie = sansMetadonnees(_jpeg(orientation: 1))!;
      // Tables, en-tête, et les deux passes d'un JPEG progressif, avec leurs
      // octets d'échappement (FF 00) et de reprise (FF D0) : tout à l'identique.
      expect(_contient(sortie, _image), isTrue);
    });

    test("ce qui suit la fin de l'image disparaît", () {
      final sortie = sansMetadonnees(_jpeg(orientation: 1))!;
      expect(sortie.sublist(sortie.length - 2), [0xFF, 0xD9]);
      expect(latin1.decode(sortie), isNot(contains('VIDEO_ANIMEE')));
    });

    test('un JPEG tronqué est refusé plutôt que mal recopié', () {
      final entier = _jpeg(orientation: 1);
      expect(sansMetadonnees(Uint8List.sublistView(entier, 0, 40)), isNull);
    });
  });

  group('PNG', () {
    test("retire l'Exif, les textes et l'heure, garde l'image et ses couleurs",
        () {
      final sortie = sansMetadonnees(_png())!;
      expect(_typesPng(sortie), ['IHDR', 'iCCP', 'IDAT', 'IEND']);
      // Les morceaux gardés sont recopiés tels quels, sommes de contrôle
      // comprises.
      expect(_contient(sortie, _morceauPng('IDAT', [1, 2, 3, 4])), isTrue);
    });
  });

  test("un format qu'on ne sait pas trier rend null", () {
    expect(sansMetadonnees(Uint8List.fromList(ascii.encode('GIF89a....'))),
        isNull);
  });
}

// ---------------------------------------------------------------------------
// Fabrication des fichiers d'essai
// ---------------------------------------------------------------------------

List<int> _segment(int marqueur, List<int> charge) => [
      0xFF,
      marqueur,
      (charge.length + 2) >> 8,
      (charge.length + 2) & 0xFF,
      ...charge,
    ];

/// L'Exif minimal attendu pour une orientation 6 (photo tenue debout).
final _exifOrientation6 = _segment(0xE1, [
  ...ascii.encode('Exif'), 0, 0, //
  0x4D, 0x4D, 0x00, 0x2A, 0, 0, 0, 8, // en-tête TIFF, grand-boutiste
  0, 1, // une entrée
  0x01, 0x12, 0, 3, 0, 0, 0, 1, 0, 6, 0, 0, // Orientation = 6
  0, 0, 0, 0, // pas d'IFD suivant
]);

/// Un Exif de téléphone : appareil, orientation, renvoi vers la position.
List<int> _exif(int orientation, {required bool grandBoutiste}) {
  List<int> u16(int v) =>
      grandBoutiste ? [v >> 8, v & 0xFF] : [v & 0xFF, v >> 8];
  List<int> u32(int v) => grandBoutiste
      ? [v >> 24, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]
      : [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, v >> 24];
  List<int> entree(int tag, int type, int nombre, List<int> valeur) =>
      [...u16(tag), ...u16(type), ...u32(nombre), ...valeur];
  // IFD0 à l'octet 8 : trois entrées (12 octets chacune) + compte + suivant.
  const finIfd = 8 + 2 + 3 * 12 + 4;
  final marque = ascii.encode('Pixel 8\u0000');
  return [
    ...ascii.encode('Exif'), 0, 0,
    ...(grandBoutiste ? [0x4D, 0x4D] : [0x49, 0x49]), ...u16(0x2A), ...u32(8),
    ...u16(3),
    ...entree(0x010F, 2, marque.length, u32(finIfd)), // Make
    ...entree(0x0112, 3, 1, [...u16(orientation), 0, 0]), // Orientation
    ...entree(0x8825, 4, 1, u32(finIfd + marque.length)), // GPS
    ...u32(0),
    ...marque,
    ...ascii.encode('GPS48.8566N2.3522E'),
    ...ascii.encode('MINIATURE'),
  ];
}

/// Tables, en-tête et deux passes (JPEG progressif) : ce qui fait l'image.
final _image = <int>[
  ..._segment(0xDB, List.filled(65, 7)), // DQT
  ..._segment(0xC2, [8, 0, 16, 0, 16, 1, 1, 0x11, 0]), // SOF2
  ..._segment(0xC4, List.filled(20, 3)), // DHT
  ..._segment(0xDA, [1, 1, 0, 0, 63, 0]), // SOS
  0x12, 0x34, 0xFF, 0x00, 0x56, 0xFF, 0xD0, 0x78, // données, FF00, RST0
  ..._segment(0xC4, List.filled(20, 4)), // DHT entre deux passes
  ..._segment(0xDA, [1, 1, 0, 1, 63, 0]), // SOS
  0x9A, 0xFF, 0x00, 0xBC,
];

Uint8List _jpeg({required int orientation, bool grandBoutiste = false}) =>
    Uint8List.fromList([
      0xFF,
      0xD8,
      ..._segment(
          0xE0, [...ascii.encode('JFIF'), 0, 1, 1, 0, 0, 1, 0, 1, 0, 0]),
      ..._segment(0xE1, _exif(orientation, grandBoutiste: grandBoutiste)),
      ..._segment(0xE1, ascii.encode('http://ns.adobe.com/xap/1.0/\u0000<x/>')),
      ..._segment(0xE2, [...ascii.encode('ICC_PROFILE'), 0, 1, 1, 9, 9, 9]),
      ..._segment(0xE2, [...ascii.encode('MPF'), 0, 1, 2, 3]),
      ..._segment(0xED, ascii.encode('Photoshop 3.0\u0000IPTC')),
      ..._segment(0xEE, [...ascii.encode('Adobe'), 0, 100, 0, 0, 0, 0, 1]),
      ..._segment(0xFE, latin1.encode('Pris chez moi')),
      ..._image,
      0xFF,
      0xD9,
      ...ascii.encode('VIDEO_ANIMEE'),
      0xFF,
      0xD8,
      0xFF,
      0xD9,
    ]);

List<int> _morceauPng(String type, List<int> donnees) => [
      0, 0, 0, donnees.length,
      ...ascii.encode(type),
      ...donnees,
      0xAA, 0xBB, 0xCC, 0xDD, // somme de contrôle, recopiée sans être lue
    ];

Uint8List _png() => Uint8List.fromList([
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      ..._morceauPng('IHDR', List.filled(13, 1)),
      ..._morceauPng('eXIf', ascii.encode('MM*Pixel 8')),
      ..._morceauPng('iCCP', [9, 9, 9]),
      ..._morceauPng('tEXt', ascii.encode('Author\u0000Marie')),
      ..._morceauPng('tIME', [7, 234, 11, 6, 12, 0, 0]),
      ..._morceauPng('IDAT', [1, 2, 3, 4]),
      ..._morceauPng('IEND', []),
    ]);

List<String> _typesPng(Uint8List o) {
  final types = <String>[];
  var i = 8;
  while (i + 8 <= o.length) {
    final longueur = ByteData.sublistView(o).getUint32(i);
    types.add(ascii.decode(o.sublist(i + 4, i + 8)));
    i += 12 + longueur;
  }
  return types;
}

bool _contient(List<int> botte, List<int> aiguille) {
  for (var i = 0; i + aiguille.length <= botte.length; i++) {
    var ok = true;
    for (var j = 0; j < aiguille.length && ok; j++) {
      ok = botte[i + j] == aiguille[j];
    }
    if (ok) return true;
  }
  return false;
}
