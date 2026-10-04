import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/data/services/enregistreur_vocal.dart';

void main() {
  test('une pause ne compte pas dans la durée du vocal', () {
    var maintenant = DateTime(2026, 10, 4, 12);
    final temps = TempsEnregistre(() => maintenant)..demarrer();

    maintenant = maintenant.add(const Duration(seconds: 5));
    expect(temps.ecoule, const Duration(seconds: 5));

    // L'écran s'éteint : l'enregistrement se met en pause trente secondes.
    temps.suspendre();
    maintenant = maintenant.add(const Duration(seconds: 30));
    expect(temps.enPause, isTrue);
    expect(temps.ecoule, const Duration(seconds: 5));

    temps.reprendre();
    maintenant = maintenant.add(const Duration(seconds: 3));
    expect(temps.ecoule, const Duration(seconds: 8));
  });

  test('une pause ou une reprise en double ne fausse rien', () {
    var maintenant = DateTime(2026, 10, 4, 12);
    final temps = TempsEnregistre(() => maintenant)..demarrer();
    maintenant = maintenant.add(const Duration(seconds: 2));
    temps
      ..suspendre()
      ..suspendre();
    maintenant = maintenant.add(const Duration(seconds: 10));
    temps
      ..reprendre()
      ..reprendre();
    maintenant = maintenant.add(const Duration(seconds: 1));
    expect(temps.ecoule, const Duration(seconds: 3));
  });

  test('avant le début et après l arrêt, rien ne s écoule', () {
    var maintenant = DateTime(2026, 10, 4, 12);
    final temps = TempsEnregistre(() => maintenant);
    expect(temps.ecoule, Duration.zero);
    temps.demarrer();
    maintenant = maintenant.add(const Duration(seconds: 4));
    temps.arreter();
    expect(temps.ecoule, Duration.zero);
  });
}
