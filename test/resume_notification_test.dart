import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/data/services/notification_service.dart';

/// Toucher le paquet replié (« Rempart · 3 conversations ») ouvre une
/// conversation, et non plus l'accueil seul : celle qui vient d'arriver.
void main() {
  String? cible({
    required List<String> enAttente,
    String? arrivee,
    String? precedente,
  }) =>
      NotificationService.conversationDuResume(
        enAttente: enAttente,
        arrivee: arrivee,
        precedente: precedente,
      );

  test('la conversation qui vient de notifier', () {
    expect(cible(enAttente: ['!a', '!b'], arrivee: '!b', precedente: '!a'), '!b');
  });

  test('un retrait garde la conversation que le résumé ouvrait déjà', () {
    expect(cible(enAttente: ['!a', '!b', '!c'], precedente: '!c'), '!c');
  });

  test("si elle vient d'être retirée, une qui attend encore", () {
    expect(cible(enAttente: ['!a', '!b'], precedente: '!c'), '!a');
  });

  test('sans précédent, la première qui attend', () {
    expect(cible(enAttente: ['!a']), '!a');
  });

  test('plus rien qui attende : aucune', () {
    expect(cible(enAttente: [], precedente: '!a'), isNull);
  });
}
