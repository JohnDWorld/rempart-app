import 'dart:typed_data';

import 'package:matrix/matrix.dart';

/// La base du SDK, avec le cache d'envoi tenu en mémoire.
///
/// Pendant qu'un média part, le SDK garde le fichier sous
/// `cache://file/<transaction>` : c'est ce que l'écho du message affiche.
/// Ouverte sans dossier de fichiers, la base n'en gardait rien sur téléphone,
/// et une bulle qui chargeait l'image d'un écho poussait le SDK à annuler
/// l'envoi (`Event._getCachedFile`, puis `cancelSend`). Cette annulation simule
/// une rédaction, qui vide le contenu du message, celui-là même qui part : si
/// elle tombe avant le chiffrement, le média part vide (première photo d'un
/// album, le 2026-11-19). Le SDK tient ce cache en mémoire sur le web ; c'est
/// ce que fait cette base, sur téléphone. Rien n'est écrit sur le disque, et
/// les médias reçus ne sont toujours pas gardés.
class BaseRempart extends MatrixSdkDatabase {
  BaseRempart(super.name, {super.database}) : super.buildWithoutOpen();

  final _envois = <Uri, Uint8List>{};

  @override
  Future<void> storeFile(Uri mxcUri, Uint8List bytes, int time) async {
    if (mxcUri.scheme != 'cache') return super.storeFile(mxcUri, bytes, time);
    _envois[mxcUri] = bytes;
  }

  @override
  Future<Uint8List?> getFile(Uri mxcUri) async {
    if (mxcUri.scheme != 'cache') return super.getFile(mxcUri);
    return _envois[mxcUri];
  }

  @override
  Future<bool> deleteFile(Uri mxcUri) async {
    if (mxcUri.scheme != 'cache') return super.deleteFile(mxcUri);
    return _envois.remove(mxcUri) != null;
  }
}
