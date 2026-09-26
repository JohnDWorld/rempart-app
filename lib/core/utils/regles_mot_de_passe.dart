import '../constants/app_constants.dart';

/// Ce qui empêche [valeur] de servir de mot de passe, ou null s'il convient.
///
/// Une seule règle pour l'inscription, le changement et la réinitialisation :
/// un mot de passe refusé à la création ne doit pas devenir acceptable par une
/// autre porte.
///
/// L'appareil est seul à pouvoir l'imposer : le serveur ne reçoit plus qu'une
/// valeur dérivée, toujours longue, et ses propres règles ne voient jamais le
/// vrai mot de passe. Elle ne s'applique pas à la connexion, où un compte créé
/// sous une règle plus ancienne doit toujours pouvoir entrer.
String? problemeMotDePasse(String valeur) {
  if (valeur.length < AppConstants.minPasswordLength) {
    return 'Le mot de passe doit contenir au moins '
        '${AppConstants.minPasswordLength} caractères';
  }
  if (!valeur.contains(RegExp('[0-9]'))) {
    return 'Le mot de passe doit contenir au moins un chiffre';
  }
  if (!valeur.contains(RegExp('[a-z]'))) {
    return 'Le mot de passe doit contenir au moins une minuscule';
  }
  return null;
}

/// La règle, telle qu'on l'annonce sous le champ.
String get consigneMotDePasse => 'Au moins ${AppConstants.minPasswordLength} '
    'caractères, avec un chiffre et une minuscule';
