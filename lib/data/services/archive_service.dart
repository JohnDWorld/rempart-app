import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service pour gérer l'archivage local des conversations
/// Les conversations archivées sont masquées mais l'utilisateur reste membre de la room
class ArchiveService {
  ArchiveService._();

  static final ArchiveService instance = ArchiveService._();

  static const String _archivedRoomsKey = 'archived_rooms';

  SharedPreferences? _prefs;

  /// Initialise le service
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Récupère la liste des IDs de rooms archivées
  Set<String> get archivedRoomIds {
    final list = _prefs?.getStringList(_archivedRoomsKey) ?? [];
    return list.toSet();
  }

  /// Vérifie si une room est archivée
  bool isArchived(String roomId) {
    return archivedRoomIds.contains(roomId);
  }

  /// Archive une conversation
  Future<void> archiveRoom(String roomId) async {
    final archived = archivedRoomIds..add(roomId);
    await _prefs?.setStringList(_archivedRoomsKey, archived.toList());
    debugPrint('ArchiveService: Room $roomId archivée');
  }

  /// Désarchive une conversation
  Future<void> unarchiveRoom(String roomId) async {
    final archived = archivedRoomIds..remove(roomId);
    await _prefs?.setStringList(_archivedRoomsKey, archived.toList());
    debugPrint('ArchiveService: Room $roomId désarchivée');
  }

  /// Désarchive toutes les conversations
  Future<void> unarchiveAll() async {
    await _prefs?.remove(_archivedRoomsKey);
    debugPrint('ArchiveService: Toutes les rooms désarchivées');
  }

  /// Nombre de conversations archivées
  int get archivedCount => archivedRoomIds.length;
}
