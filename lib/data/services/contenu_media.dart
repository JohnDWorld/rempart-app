import 'package:matrix/matrix.dart';

/// Le message qui annonce un média déjà téléversé.
///
/// Repris de `Room.sendFileEvent` (SDK 7.4.0), qui enchaîne téléversement et
/// annonce sans laisser les séparer : c'est ce qui empêchait d'envoyer un
/// album d'un bloc (voir `MatrixService.envoyerAlbum`). Le contenu doit rester
/// celui du SDK, que les autres clients savent lire : à revoir à chaque
/// montée de version du SDK.
///
/// [chiffre] et [vignetteChiffree] portent les clés quand le salon est
/// chiffré ; l'adresse est alors dans `file.url`, jamais dans `url`.
Map<String, dynamic> contenuDuMedia({
  required MatrixFile fichier,
  required Uri url,
  EncryptedFile? chiffre,
  MatrixImageFile? vignette,
  Uri? urlVignette,
  EncryptedFile? vignetteChiffree,
  Map<String, dynamic>? extra,
}) =>
    {
      'msgtype': fichier.msgType,
      'body': fichier.name,
      'filename': fichier.name,
      if (chiffre == null) 'url': url.toString(),
      if (chiffre != null)
        'file': _fichierChiffre(url, fichier.mimeType, chiffre),
      'info': {
        ...fichier.info,
        if (vignette != null && vignetteChiffree == null)
          'thumbnail_url': urlVignette.toString(),
        if (vignette != null && vignetteChiffree != null)
          'thumbnail_file':
              _fichierChiffre(urlVignette!, vignette.mimeType, vignetteChiffree),
        if (vignette != null) 'thumbnail_info': vignette.info,
        if (vignette?.blurhash != null &&
            fichier is MatrixImageFile &&
            fichier.blurhash == null)
          'xyz.amorgan.blurhash': vignette!.blurhash,
      },
      if (extra != null) ...extra,
    };

Map<String, dynamic> _fichierChiffre(
  Uri url,
  String mimeType,
  EncryptedFile chiffre,
) =>
    {
      'url': url.toString(),
      'mimetype': mimeType,
      'v': 'v2',
      'key': {
        'alg': 'A256CTR',
        'ext': true,
        'k': chiffre.k,
        'key_ops': ['encrypt', 'decrypt'],
        'kty': 'oct',
      },
      'iv': chiffre.iv,
      'hashes': {'sha256': chiffre.sha256},
    };
