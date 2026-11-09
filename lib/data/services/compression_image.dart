import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../../core/plateforme.dart';
import '../../core/utils/metadonnees_image.dart';

/// Réduit une photo avant l'envoi, sauf demande contraire.
///
/// Une photo de téléphone pèse aujourd'hui entre 3 et 12 Mo pour 4000 pixels
/// de large, quand un écran en affiche 1200. L'envoyer telle quelle coûte du
/// réseau à qui l'envoie, du stockage au serveur, et du temps à qui la reçoit,
/// pour une différence que personne ne voit.
///
/// L'original reste accessible : c'est le sens de l'interrupteur « HD ». Il
/// vaut pour ce qu'on veut garder intact, un document photographié ou une
/// image qu'on recadrera.
class CompressionImage {
  CompressionImage._();

  /// Côté le plus long après réduction.
  ///
  /// 1600 px : au-delà, l'écran d'un téléphone n'y gagne rien, et le poids
  /// croît avec le carré de la dimension.
  static const _coteMax = 1600;

  /// Qualité JPEG. 85 est le point où l'oeil cesse de distinguer la perte,
  /// alors que le poids, lui, continue de baisser.
  static const _qualite = 85;

  /// En dessous, comprimer ne rapporte rien et peut même alourdir (une image
  /// déjà optimisée, une capture d'écran, un dessin).
  static const _seuilOctets = 300 * 1024;

  /// Rend une version allégée, ou les octets d'origine si ça n'a pas de sens.
  ///
  /// Ne lève jamais : une compression qui échoue rend l'original. Mieux vaut
  /// une photo lourde qu'une photo perdue.
  static Future<Uint8List> alleger(Uint8List octets, String mimeType) async {
    // Le web n'a pas le codec natif, et les vidéos ne passent pas par ici.
    if (estWeb || !mimeType.startsWith('image/')) return octets;
    // Un PNG transparent recomprimé en JPEG perdrait sa transparence, et un
    // GIF son animation.
    if (mimeType != 'image/jpeg' && mimeType != 'image/heic') return octets;
    if (octets.lengthInBytes <= _seuilOctets) return octets;

    try {
      final reduit = await FlutterImageCompress.compressWithList(
        octets,
        minWidth: _coteMax,
        minHeight: _coteMax,
        quality: _qualite,
      );
      // Une image déjà petite ou déjà comprimée peut ressortir plus lourde :
      // on garde alors ce qu'on avait.
      return reduit.lengthInBytes < octets.lengthInBytes ? reduit : octets;
    } catch (e) {
      debugPrint('Compression: image gardée telle quelle ($e)');
      return octets;
    }
  }

  /// La photo sans ce qu'elle dit d'elle-même (`sansMetadonnees` : position,
  /// appareil, heure), et son vrai type : une photo HEIC allégée est déjà un
  /// JPEG, que son type annonçait encore comme HEIC.
  ///
  /// Un HEIC (celui des Samsung réglés ainsi) n'a pas de tri sans perte ici :
  /// il devient un JPEG à pleine taille, qualité 95, que la version web et
  /// les autres clients affichent de toute façon mieux. Le web n'a pas le
  /// codec, son HEIC part tel quel.
  static Future<(Uint8List, String)> sansTraces(
    Uint8List octets,
    String mimeType,
  ) async {
    final trie = sansMetadonnees(octets);
    if (trie != null) {
      return (trie, trie[0] == 0xFF ? 'image/jpeg' : 'image/png');
    }
    if (estWeb || !_estHeif(octets)) return (octets, mimeType);
    try {
      // ponytail: décode le HEIC entier en mémoire ; un 50 Mpx peut manquer
      // de place sur un petit téléphone, et part alors tel quel.
      final jpeg = await FlutterImageCompress.compressWithList(
        octets,
        // L'échelle ne descend jamais sous 1 : aucune réduction.
        minWidth: 1 << 16,
        minHeight: 1 << 16,
        // Le défaut du paquet, écrit quand même : il décide de ce que vaut
        // une photo HD, il ne doit pas changer à la faveur d'une mise à jour.
        // ignore: avoid_redundant_argument_values
        quality: 95,
      );
      return (sansMetadonnees(jpeg) ?? jpeg, 'image/jpeg');
    } catch (e) {
      debugPrint('Métadonnées: HEIC gardé tel quel ($e)');
      return (octets, mimeType);
    }
  }

  /// `ftyp` puis une marque HEIF (heic, heix, heif, mif1...).
  static bool _estHeif(Uint8List o) {
    if (o.length < 12) return false;
    final boite = String.fromCharCodes(o, 4, 8);
    final marque = String.fromCharCodes(o, 8, 12);
    return boite == 'ftyp' && (marque.startsWith('he') || marque == 'mif1');
  }

  /// Ce que pèsera l'envoi, pour le dire avant de l'engager.
  static String poidsLisible(int octets) {
    if (octets >= 1024 * 1024) {
      return '${(octets / 1024 / 1024).toStringAsFixed(1)} Mo';
    }
    return '${(octets / 1024).round()} Ko';
  }
}
