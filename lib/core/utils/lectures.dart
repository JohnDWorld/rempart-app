import 'package:intl/intl.dart';

/// Qui a lu un message, et qui pas encore.
class Lectures {
  const Lectures(this.lu, this.pasLu);

  /// Du premier au dernier lecteur.
  final List<({String mxid, DateTime quand})> lu;

  /// Dans l'ordre des destinataires.
  final List<String> pasLu;
}

/// Répartit les destinataires d'un message entre ceux qui l'ont lu et les
/// autres.
///
/// Même règle que la double coche (`Event.luParUnAutre`) : un accusé Matrix ne
/// désigne que le DERNIER message lu, les précédents n'en portent aucun. On
/// compare donc l'heure de cet accusé à celle de l'envoi, et c'est elle qu'on
/// affiche : au plus tard à ce moment, la personne avait lu le message.
/// Seuls les destinataires comptent : l'accusé d'un ancien membre ne doit pas
/// faire apparaître un inconnu.
Lectures lecturesDe({
  required DateTime envoye,
  required Map<String, DateTime> accuses,
  required Iterable<String> destinataires,
}) {
  final lu = <({String mxid, DateTime quand})>[];
  final pasLu = <String>[];
  for (final mxid in destinataires) {
    final quand = accuses[mxid];
    if (quand != null && !quand.isBefore(envoye)) {
      lu.add((mxid: mxid, quand: quand));
    } else {
      pasLu.add(mxid);
    }
  }
  lu.sort((a, b) => a.quand.compareTo(b.quand));
  return Lectures(lu, pasLu);
}

/// L'heure d'une lecture, dite comme dans une conversation.
String quandLisible(DateTime quand, DateTime maintenant) {
  final jour = DateTime(quand.year, quand.month, quand.day);
  final aujourdhui = DateTime(maintenant.year, maintenant.month, maintenant.day);
  final heure = DateFormat('HH:mm', 'fr_FR').format(quand);
  if (jour == aujourdhui) return "aujourd'hui à $heure";
  if (jour == aujourdhui.subtract(const Duration(days: 1))) return 'hier à $heure';
  return "${DateFormat('d MMM y', 'fr_FR').format(quand)} à $heure";
}

/// La date complète d'un envoi, à la seconde.
String dateComplete(DateTime quand) =>
    DateFormat("EEEE d MMMM y 'à' HH:mm:ss", 'fr_FR').format(quand);
