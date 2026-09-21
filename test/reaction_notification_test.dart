import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/core/utils/apercu_notification.dart';

/// Ce qu'annonce une notification de réaction.
///
/// Le texte est composé au même endroit que celui des messages, mais il est
/// lu dans un contexte différent : sur un écran verrouillé, « a réagi ✅ »
/// doit se comprendre sans ouvrir l'application.
void main() {
  test('en tête-à-tête, le titre est le contact', () {
    final a = composerApercu(
      texte: 'a réagi 👍 à votre message',
      nomExpediteur: 'Bérénice',
    );
    expect(a.titre, 'Bérénice');
    expect(a.corps, 'a réagi 👍 à votre message');
  });

  test('dans un groupe, on sait QUI a réagi', () {
    // Sans le nom dans le corps, trois réactions de trois personnes seraient
    // indiscernables sous le seul nom du groupe.
    final a = composerApercu(
      texte: 'a réagi ✅ à votre message',
      nomExpediteur: 'Heimdall',
      nomRoom: 'Interventions',
    );
    expect(a.titre, 'Interventions');
    expect(a.corps, 'Heimdall : a réagi ✅ à votre message');
  });

  test('un expéditeur non résolu ne laisse pas d identifiant', () {
    // Jamais de mxid sur un écran verrouillé : le repli est un mot, pas un
    // identifiant technique.
    final a = composerApercu(texte: 'a réagi ❤️ à votre message');
    expect(a.titre, 'Rempart');
    expect(a.corps, contains('a réagi'));
    expect(a.corps, isNot(contains('@')));
  });
}
