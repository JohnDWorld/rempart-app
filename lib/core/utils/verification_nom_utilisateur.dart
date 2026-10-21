import 'dart:async';

import 'package:flutter/foundation.dart';

import 'nom_utilisateur.dart';

/// Ce qu'on sait du nom d'utilisateur en cours de saisie.
enum EtatNomUtilisateur { inconnu, verification, disponible, refuse }

/// Vérifie un nom d'utilisateur pendant la frappe : règles, puis
/// disponibilité auprès de la base, une fois la saisie arrêtée ([delai]).
///
/// Jusqu'au 2026-10-21, on n'apprenait qu'un nom était pris qu'en validant le
/// formulaire. La vérification à l'envoi reste : entre la frappe et l'envoi,
/// quelqu'un a pu le prendre, et la base seule tranche (index unique).
class VerificationNomUtilisateur extends ChangeNotifier {
  VerificationNomUtilisateur(
    this._refusDe, {
    this.delai = const Duration(milliseconds: 500),
  });

  /// Le refus de la base pour un nom (`nom_utilisateur_disponible`), ou null.
  final Future<String?> Function(String nom) _refusDe;
  final Duration delai;

  EtatNomUtilisateur etat = EtatNomUtilisateur.inconnu;

  /// Le message à poser sous le champ quand [etat] est `refuse`.
  String? erreur;

  String _nom = '';
  Timer? _minuteur;
  bool _ferme = false;

  /// Ce qu'on dit sous le champ quand le nom est libre.
  String? get annonce =>
      etat == EtatNomUtilisateur.disponible ? '@$_nom est disponible' : null;

  /// La saisie vient de changer. [actuel] est son propre nom, qui n'est pas
  /// « pris » pour soi et ne se revérifie pas.
  void saisie(String texte, {String? actuel}) {
    _minuteur?.cancel();
    _nom = normaliserNomUtilisateur(texte);
    _poser(EtatNomUtilisateur.inconnu, null);
    if (_nom.isEmpty ||
        (actuel != null && _nom == normaliserNomUtilisateur(actuel))) {
      return;
    }
    _minuteur = Timer(delai, _verifier);
  }

  Future<void> _verifier() async {
    final nom = _nom;
    final probleme = problemeNomUtilisateur(nom);
    if (probleme != null) {
      _poser(EtatNomUtilisateur.refuse, probleme);
      return;
    }
    _poser(EtatNomUtilisateur.verification, null);
    String? refus;
    try {
      refus = await _refusDe(nom);
    } catch (e) {
      // Réseau absent : rien à dire, la base tranchera à l'envoi.
      debugPrint("Nom d'utilisateur : disponibilité inconnue ($e)");
      if (nom == _nom) _poser(EtatNomUtilisateur.inconnu, null);
      return;
    }
    // La saisie a changé pendant la question : la réponse ne vaut plus.
    if (nom != _nom) return;
    if (refus == null) {
      _poser(EtatNomUtilisateur.disponible, null);
    } else {
      _poser(EtatNomUtilisateur.refuse, messageRefusNomUtilisateur(refus, nom));
    }
  }

  void _poser(EtatNomUtilisateur nouvel, String? message) {
    if (_ferme || (etat == nouvel && erreur == message)) return;
    etat = nouvel;
    erreur = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _ferme = true;
    _minuteur?.cancel();
    super.dispose();
  }
}
