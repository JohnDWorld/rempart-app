import 'package:matrix/matrix.dart';

/// Le chiffrement de bout en bout ne tourne pas sur cet appareil.
///
/// Sous-classe de [MatrixException] à dessein : le SDK marque alors le message
/// en échec aussitôt. Toute autre exception, il la prendrait pour une panne
/// passagère et réessaierait chaque seconde pendant une minute.
class ChiffrementIndisponible extends MatrixException {
  ChiffrementIndisponible()
      : super.fromJson({
          'errcode': 'FR_REMPART_CHIFFREMENT_INDISPONIBLE',
          'error': _message,
        });

  static const _message = "le chiffrement n'est pas disponible sur cet "
      'appareil. Relancez Rempart, puis réessayez.';

  @override
  String toString() => _message;
}

/// Ce type d'événement peut-il partir tel quel dans ce salon ?
///
/// Dans un salon chiffré, seul passe ce que le protocole laisse en clair de
/// toute façon : l'événement chiffré lui-même, et la réaction, faite d'une
/// seule relation (le SDK ne la chiffre jamais).
bool envoiAdmis({required bool salonChiffre, required String type}) =>
    !salonChiffre ||
    type == EventTypes.Encrypted ||
    type == EventTypes.Reaction;

/// Client Matrix qui refuse d'écrire en clair dans un salon chiffré.
///
/// Le SDK ne chiffre un message que si le chiffrement tourne sur l'appareil
/// (`encrypted && client.encryptionEnabled`, dans `Room._sendContent`) : si
/// vodozemac n'a pas démarré, il envoie le message EN CLAIR dans le salon
/// chiffré, sans un mot. Le serveur lit alors ce que l'interface présente
/// comme chiffré. Tout message passe par [sendMessage], y compris ceux que le
/// SDK renvoie de lui-même après une coupure : c'est donc ici, et nulle part
/// ailleurs, que le refus est sûr d'être appliqué.
///
/// Les pièces jointes échappent à ce verrou : le SDK téléverse le fichier
/// AVANT d'envoyer le message qui le décrit. `MatrixService` les arrête donc
/// en amont.
class ClientRempart extends Client {
  ClientRempart(
    super.clientName, {
    required super.database,
    super.verificationMethods,
  });

  @override
  Future<String> sendMessage(
    String roomId,
    String eventType,
    String txnId,
    Map<String, Object?> body,
  ) async {
    final salon = getRoomById(roomId);
    if (!envoiAdmis(salonChiffre: salon?.encrypted ?? false, type: eventType)) {
      Logs().e('Envoi en clair refusé dans un salon chiffré ($eventType)');
      throw ChiffrementIndisponible();
    }
    return super.sendMessage(roomId, eventType, txnId, body);
  }
}
