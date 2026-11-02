// Canal officiel de Rempart : destinations d'envoi.
//
// Fonction pure, générique sur l'élément (une `Room` en production), pour se
// tester sans client Matrix.

/// Les salons où l'on peut proposer d'envoyer : ni le canal officiel, ni un
/// salon où l'on n'a pas le droit d'écrire.
List<T> destinationsEnvoi<T>(
  Iterable<T> salons, {
  required bool Function(T) estCanal,
  required bool Function(T) peutEcrire,
}) => [
  for (final s in salons)
    if (!estCanal(s) && peutEcrire(s)) s,
];
