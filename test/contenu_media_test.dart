import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:rempart_app/data/services/contenu_media.dart';

/// Le message d'un média d'album, composé par Rempart et non plus par le SDK
/// (voir `MatrixService.envoyerAlbum`). Il doit rester celui du SDK : c'est
/// ce que les autres clients, et Rempart lui-même, savent lire.
void main() {
  final photo = MatrixImageFile(
    bytes: Uint8List(2048),
    name: 'plage.jpg',
    mimeType: 'image/jpeg',
    width: 1600,
    height: 1200,
  );
  final vignette = MatrixImageFile(
    bytes: Uint8List(256),
    name: 'plage.jpg',
    mimeType: 'image/jpeg',
    width: 800,
    height: 600,
  );
  EncryptedFile cles(String k) =>
      EncryptedFile(data: Uint8List(0), k: k, iv: 'iv-$k', sha256: 'h-$k');
  final album = {'fr.rempart.album': {'id': 'alb_1'}};

  test('salon en clair : adresse directe, album et légende', () {
    final c = contenuDuMedia(
      fichier: photo,
      url: Uri.parse('mxc://rempart.test/photo'),
      extra: {'body': 'Le coucher de soleil', ...album},
    );
    expect(c['msgtype'], MessageTypes.Image);
    expect(c['url'], 'mxc://rempart.test/photo');
    expect(c.containsKey('file'), isFalse);
    // La légende remplace le nom dans `body`, le nom reste dans `filename`.
    expect(c['body'], 'Le coucher de soleil');
    expect(c['filename'], 'plage.jpg');
    expect(c['fr.rempart.album'], {'id': 'alb_1'});
    expect(c['info'], containsPair('w', 1600));
    expect(c['info'], containsPair('size', 2048));
  });

  test('salon chiffré : adresse et clés dans `file`, jamais dans `url`', () {
    final c = contenuDuMedia(
      fichier: photo,
      url: Uri.parse('mxc://rempart.test/chiffre'),
      chiffre: cles('a'),
      vignette: vignette,
      urlVignette: Uri.parse('mxc://rempart.test/vignette'),
      vignetteChiffree: cles('b'),
      extra: album,
    );
    expect(c.containsKey('url'), isFalse);
    final fichier = c['file'] as Map<String, dynamic>;
    expect(fichier['url'], 'mxc://rempart.test/chiffre');
    expect(fichier['v'], 'v2');
    expect((fichier['key'] as Map)['k'], 'a');
    expect(fichier['iv'], 'iv-a');
    expect(fichier['hashes'], {'sha256': 'h-a'});

    final info = c['info'] as Map<String, dynamic>;
    expect(info.containsKey('thumbnail_url'), isFalse);
    final miniature = info['thumbnail_file'] as Map<String, dynamic>;
    expect(miniature['url'], 'mxc://rempart.test/vignette');
    expect((miniature['key'] as Map)['k'], 'b');
    expect(info['thumbnail_info'], containsPair('w', 800));
    expect(c['body'], 'plage.jpg');
  });
}
