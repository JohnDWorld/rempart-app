import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:rempart_app/data/services/statut_presence.dart';

void main() {
  test('automatique : en ligne à l écran, absent en arrière-plan', () {
    expect(
      presenceAnnoncee(StatutChoisi.automatique, premierPlan: true),
      PresenceType.online,
    );
    expect(
      presenceAnnoncee(StatutChoisi.automatique, premierPlan: false),
      PresenceType.unavailable,
    );
  });

  test('absent et invisible ne passent jamais en ligne', () {
    for (final premierPlan in [true, false]) {
      expect(
        presenceAnnoncee(StatutChoisi.absent, premierPlan: premierPlan),
        PresenceType.unavailable,
      );
      expect(
        presenceAnnoncee(StatutChoisi.invisible, premierPlan: premierPlan),
        PresenceType.offline,
      );
    }
  });
}
