import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/plateforme.dart';
import '../models/matrix_extensions.dart';

/// Le son d'un vocal, joint à sa notification.
///
/// Sans lui, Android Auto lit à voix haute le texte de la notification, et
/// annonce « Message vocal » au lieu de le faire entendre. Avec, il joue le
/// fichier : c'est ce que fait Telegram (`setData("audio/ogg", …)` sur le
/// message de la notification), dont les vocaux s'écoutent en voiture.
///
/// Le vocal est déchiffré sur l'appareil et écrit dans un dossier privé de
/// l'application (exclu des sauvegardes comme le reste), que seul le
/// FileProvider désigne (`chemins_maj.xml`, entrée `vocaux`) : Android n'en
/// ouvre la lecture qu'au système et aux lecteurs de notifications, Android
/// Auto compris. Il est effacé quand la notification part.
const _dossier = 'vocaux_notif';

/// Au-delà, on ne télécharge pas en arrière-plan : un vocal pèse quelques
/// centaines de kilo-octets, un fichier audio quelconque peut peser bien plus.
const _tailleMax = 10 * 1024 * 1024;

/// Nom du fichier d'un vocal : la conversation en tête, pour effacer d'un coup
/// les vocaux d'une notification qui part ; l'événement ensuite, réduit aux
/// caractères sûrs dans un nom de fichier comme dans une adresse.
@visibleForTesting
String nomFichierVocal({
  required String roomId,
  required String eventId,
  required String mime,
}) {
  final extension = mime.contains('ogg')
      ? 'ogg'
      : mime.contains('mpeg')
          ? 'mp3'
          : 'm4a';
  final evenement = eventId.replaceAll(RegExp('[^A-Za-z0-9_-]'), '');
  return '${_prefixe(roomId)}$evenement.$extension';
}

String _prefixe(String roomId) => '${roomId.hashCode}_';

Future<Directory> _dossierVocaux() async {
  final base = await getApplicationSupportDirectory();
  return Directory('${base.path}/$_dossier');
}

/// Écrit le son de [event] là où sa notification peut le désigner, et rend de
/// quoi l'y joindre. Null hors Android, pour ce qui n'est pas un son, ou si
/// quoi que ce soit échoue : la notification part alors sans, comme avant.
Future<({String mime, String uri})?> vocalPourNotification(Event event) async {
  if (!estAndroid || !event.isAudioMessage) return null;
  try {
    final taille = event.infoMap['size'];
    if (taille is int && taille > _tailleMax) return null;
    final fichier = await event.downloadAndDecryptAttachment();
    final mime = event.attachmentMimetype.isEmpty
        ? 'audio/mp4'
        : event.attachmentMimetype;
    final nom = nomFichierVocal(
      roomId: event.room.id,
      eventId: event.eventId,
      mime: mime,
    );
    final dossier = await _dossierVocaux();
    await dossier.create(recursive: true);
    await File('${dossier.path}/$nom').writeAsBytes(fichier.bytes, flush: true);
    final paquet = (await PackageInfo.fromPlatform()).packageName;
    return (mime: mime, uri: 'content://$paquet.maj/vocaux/$nom');
  } catch (e) {
    debugPrint('Notification: vocal non joint ($e)');
    return null;
  }
}

/// Efface les vocaux d'une conversation dont la notification est partie, ou
/// tous sans [roomId] (déconnexion). Avec [plusVieuxQue], seulement ceux-là :
/// une notification balayée ne prévient pas l'application, et son vocal,
/// déchiffré, resterait sinon indéfiniment.
Future<void> effacerVocaux({String? roomId, Duration? plusVieuxQue}) async {
  if (!estAndroid) return;
  try {
    final dossier = await _dossierVocaux();
    if (!dossier.existsSync()) return;
    final limite =
        plusVieuxQue == null ? null : DateTime.now().subtract(plusVieuxQue);
    await for (final entree in dossier.list()) {
      if (entree is! File) continue;
      final nom = entree.uri.pathSegments.last;
      if (roomId != null && !nom.startsWith(_prefixe(roomId))) continue;
      if (limite != null && entree.lastModifiedSync().isAfter(limite)) continue;
      await entree.delete();
    }
  } catch (e) {
    debugPrint('Notification: vocaux non effacés ($e)');
  }
}
