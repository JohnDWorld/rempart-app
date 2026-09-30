import 'dart:typed_data';

import 'package:matrix/matrix.dart' as matrix;

import '../../core/utils/dimensions_image.dart';

/// Une image téléchargée et déchiffrée, avec ses proportions.
class MediaCharge {
  const MediaCharge(this.octets, this.ratio);

  final Uint8List octets;

  /// Largeur sur hauteur, ou null si l'en-tête n'a pas pu être lu.
  final double? ratio;
}

/// Images déjà déchiffrées, gardées en mémoire le temps de la session.
///
/// Sans elles, rouvrir une conversation retéléchargeait et redéchiffrait
/// chaque photo : les vignettes repassaient par leur indicateur de chargement,
/// et le fil changeait de hauteur à chaque arrivée. Servies d'ici, elles
/// s'affichent dès la première image.
///
/// Les moins récemment vues partent d'abord, au-delà de [plafond] octets.
class CacheMedias {
  CacheMedias({this.plafond = 64 * 1024 * 1024});

  static final instance = CacheMedias();

  final int plafond;

  /// Une table Dart garde l'ordre d'insertion, qui sert ici d'ordre de
  /// récence : la première clé est la moins récemment vue.
  final _entrees = <String, MediaCharge>{};

  /// Chargements en cours : deux vignettes du même média (la bulle et la
  /// visionneuse) n'en déclenchent qu'un.
  final _enCours = <String, Future<MediaCharge>>{};

  int _total = 0;

  /// Le média s'il est déjà là, sans attendre ; le rend aussi plus récent.
  MediaCharge? deja(String cle) {
    final media = _entrees.remove(cle);
    if (media != null) _entrees[cle] = media;
    return media;
  }

  Future<MediaCharge> obtenir(
    String cle,
    Future<MediaCharge> Function() charger,
  ) {
    final media = deja(cle);
    if (media != null) return Future.value(media);
    // `whenComplete` en accolades, surtout pas `=> _enCours.remove(cle)` :
    // `remove` rendrait ce même Future, que `whenComplete` attendrait alors,
    // et le chargement ne finirait jamais.
    return _enCours[cle] ??= charger().then((media) {
      _ranger(cle, media);
      return media;
    }).whenComplete(() {
      _enCours.remove(cle);
    });
  }

  void _ranger(String cle, MediaCharge media) {
    final ancien = _entrees.remove(cle);
    if (ancien != null) _total -= ancien.octets.length;
    _entrees[cle] = media;
    _total += media.octets.length;
    // Le dernier arrivé reste, même seul au-dessus du plafond : c'est celui
    // qu'on est en train de regarder.
    while (_total > plafond && _entrees.length > 1) {
      _total -= _entrees.remove(_entrees.keys.first)!.octets.length;
    }
  }
}

/// Identité d'un média qui ne change pas quand l'envoi aboutit.
///
/// Un message envoyé d'ici naît avec un identifiant provisoire, remplacé par
/// celui du serveur à la réception : la clé de transaction, elle, reste.
String cleMedia(matrix.Event event) => event.transactionId ?? event.eventId;

/// L'image d'un message, depuis la mémoire si elle y est déjà.
Future<MediaCharge> chargerImage(matrix.Event event) =>
    CacheMedias.instance.obtenir(cleMedia(event), () async {
      // Aussi pour les salons en clair : dans un salon chiffré, l'adresse du
      // média ne rend que du chiffré.
      final fichier = await event.downloadAndDecryptAttachment();
      final dimensions = await dimensionsImage(fichier.bytes);
      return MediaCharge(
        fichier.bytes,
        dimensions == null ? null : dimensions.$1 / dimensions.$2,
      );
    });
