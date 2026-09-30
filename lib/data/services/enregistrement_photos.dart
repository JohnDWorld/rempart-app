import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/plateforme.dart';
import '../models/matrix_extensions.dart';

/// Enregistrement automatique des photos reçues dans la galerie du
/// téléphone, dans l'album « Rempart », comme le fait WhatsApp.
///
/// Désactivé par défaut, et pour une raison qui tient à Rempart : une photo
/// enregistrée sort du chiffrement de bout en bout. Les autres applications
/// y ont accès, et la sauvegarde de la galerie (Google Photos, iCloud)
/// l'emporte hors de l'appareil. À l'utilisateur de le décider.
///
/// Seules les photos reçues APRÈS l'activation sont enregistrées : activer
/// l'option ne doit pas déverser tout l'historique dans la galerie. Celles
/// arrivées application fermée le sont à la synchronisation suivante.
class EnregistrementPhotos {
  EnregistrementPhotos._();

  static final instance = EnregistrementPhotos._();

  /// Instant de l'activation, en millisecondes ; absent = désactivé.
  static const _cleDepuis = 'enregistrement_photos_depuis';

  /// Événements déjà enregistrés : une photo revue par une synchronisation
  /// (reconnexion, redémarrage) ne doit pas entrer deux fois.
  static const _cleFaits = 'enregistrement_photos_faits';
  static const _maxFaits = 500;

  static const album = 'Rempart';

  /// La galerie n'existe que sur un téléphone.
  static bool get disponible => estAndroid || estIOS;

  DateTime? _depuis;
  StreamSubscription<matrix.Event>? _abonnement;

  /// Une photo à la fois : vingt photos reçues ensemble ne lancent pas vingt
  /// téléchargements.
  Future<void> _file = Future.value();

  bool get actif => _depuis != null;

  /// Relit le réglage. À appeler avant [ecouter].
  Future<void> charger() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final depuis = prefs.getInt(_cleDepuis);
      _depuis =
          depuis == null ? null : DateTime.fromMillisecondsSinceEpoch(depuis);
    } catch (_) {
      _depuis = null;
    }
  }

  /// Demande l'accès à la galerie puis active. Faux si l'accès est refusé.
  Future<bool> activer() async {
    if (!disponible) return false;
    if (!await Gal.requestAccess(toAlbum: true)) return false;
    final maintenant = DateTime.now();
    _depuis = maintenant;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_cleDepuis, maintenant.millisecondsSinceEpoch);
    return true;
  }

  Future<void> desactiver() async {
    _depuis = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cleDepuis);
  }

  /// Suit les nouveaux messages d'un client connecté.
  ///
  /// `onTimelineEvent` et non `onNotification` : une conversation en
  /// sourdine ne notifie pas, ses photos doivent pourtant être enregistrées.
  Future<void> ecouter(matrix.Client client) async {
    if (!disponible) return;
    await charger();
    await _abonnement?.cancel();
    _abonnement = client.onTimelineEvent.stream.listen(_surEvenement);
  }

  void _surEvenement(matrix.Event event) {
    final depuis = _depuis;
    if (depuis == null) return;
    if (!aEnregistrer(event, depuis: depuis, moi: event.room.client.userID)) {
      return;
    }
    _file = _file.then((_) => _enregistrer(event));
  }

  Future<void> _enregistrer(matrix.Event event) async {
    // Désactivé entre-temps : les photos encore en file restent où elles sont.
    if (!actif) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final faits = prefs.getStringList(_cleFaits) ?? <String>[];
      if (faits.contains(event.eventId)) return;

      final fichier = await event.downloadAndDecryptAttachment();
      await Gal.putImageBytes(
        fichier.bytes,
        album: album,
        name: 'Rempart_${event.originServerTs.millisecondsSinceEpoch}',
      );

      faits.add(event.eventId);
      if (faits.length > _maxFaits) {
        faits.removeRange(0, faits.length - _maxFaits);
      }
      await prefs.setStringList(_cleFaits, faits);
    } catch (e) {
      // Galerie pleine, accès retiré depuis les réglages, média illisible :
      // la photo reste dans la conversation, rien n'est perdu.
      debugPrint('EnregistrementPhotos : photo non enregistrée ($e)');
    }
  }
}

/// La photo doit-elle partir dans la galerie ?
///
/// Une photo REÇUE, arrivée après l'activation. Les siennes n'y vont pas :
/// elles viennent de la galerie ou de l'appareil photo, elles y sont déjà.
bool aEnregistrer(
  matrix.Event event, {
  required DateTime depuis,
  required String? moi,
}) =>
    event.isImageMessage &&
    event.senderId != moi &&
    !event.originServerTs.isBefore(depuis);
