import 'package:supabase_flutter/supabase_flutter.dart';

/// Cette erreur, relayée par le flux d'authentification, vient-elle d'un lien
/// de courriel refusé ?
///
/// Le flux de Supabase relaie aussi les pannes de la session elle-même : un
/// renouvellement coupé par le réseau, une session expirée. Les prendre pour
/// un lien refusé enverrait sur « Mot de passe oublié », avec « Ce lien n'est
/// plus valable », quelqu'un qui n'a ouvert aucun lien.
///
/// Un lien refusé se reconnaît à l'une de ces formes :
/// - l'adresse de retour porte l'erreur du serveur (`error=access_denied`,
///   `error_code=otp_expired`), que Supabase relève en `AuthException` avec
///   l'erreur dans `code` et son détail dans `statusCode` ;
/// - l'échange du code échoue sur un appareil qui n'a pas demandé le lien
///   (`AuthPKCEGrantCodeExchangeError`) ;
/// - le serveur refuse le code, périmé ou déjà servi (`flow_state_expired`,
///   `flow_state_not_found`, `bad_code_verifier`).
bool erreurDeLien(Object erreur) {
  if (erreur is AuthPKCEGrantCodeExchangeError) return true;
  if (erreur is! AuthException) return false;
  if (erreur is AuthRetryableFetchException ||
      erreur is AuthSessionMissingException) {
    return false;
  }
  return _codesDeLien.contains(erreur.code) ||
      _codesDeLien.contains(erreur.statusCode);
}

const _codesDeLien = {
  'access_denied',
  'otp_expired',
  'flow_state_expired',
  'flow_state_not_found',
  'bad_code_verifier',
};
