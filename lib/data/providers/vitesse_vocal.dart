import 'package:flutter_riverpod/legacy.dart';

/// Vitesse d'écoute des messages vocaux, partagée par toutes les bulles.
///
/// Partagée et non propre à chaque message : on choisit une vitesse d'écoute,
/// pas la vitesse d'un vocal en particulier. La reposer à chaque message
/// obligerait à la redire dix fois dans une conversation qui en compte dix.
///
/// Non enregistrée sur le disque, à la différence de [TailleTexte] : c'est un
/// réglage du moment (les mains prises, un vocal qui s'éternise), pas une
/// préférence durable, et retrouver x2 le lendemain sans l'avoir demandé
/// surprendrait plus que cela ne rendrait service.
final vitesseVocalProvider = StateProvider<double>((ref) => 1);

/// Les crans, dans l'ordre du cycle : un appui passe au suivant.
///
/// Trois et pas davantage : au-delà, le bouton devient un réglage qu'il faut
/// viser, alors qu'il doit se toucher sans regarder.
const vitessesVocal = <double>[1, 1.5, 2];

/// Libellé d'un cran, virgule française comprise.
String libelleVitesseVocal(double vitesse) =>
    vitesse == vitesse.roundToDouble()
        ? 'x${vitesse.toInt()}'
        : 'x${vitesse.toString().replaceAll('.', ',')}';

/// Le cran qui suit [actuelle] dans le cycle, en revenant au début après le
/// dernier. Une vitesse inconnue (réglage d'une version antérieure) ramène au
/// premier cran plutôt que de bloquer le bouton.
double vitesseSuivante(double actuelle) {
  final rang = vitessesVocal.indexOf(actuelle);
  return vitessesVocal[(rang + 1) % vitessesVocal.length];
}
