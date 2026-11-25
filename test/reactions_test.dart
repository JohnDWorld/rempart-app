import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/core/utils/reactions.dart';

void main() {
  const moi = '@moi:r';
  const lea = '@lea:r';
  const hugo = '@hugo:r';

  test('regroupe par symbole, dans l ordre, avec qui a réagi', () {
    final groupes = regrouperReactions([
      (expediteur: lea, symbole: '👍', retiree: false),
      (expediteur: moi, symbole: '❤️', retiree: false),
      (expediteur: hugo, symbole: '👍', retiree: false),
    ], moi);
    expect(groupes.map((g) => g.symbole), ['👍', '❤️']);
    expect(groupes[0].expediteurs, [lea, hugo]);
    expect(groupes[0].nombre, 2);
    expect(groupes[0].parMoi, isFalse);
    expect(groupes[1].expediteurs, [moi]);
    expect(groupes[1].parMoi, isTrue);
  });

  test('une réaction retirée ou sans symbole ne compte pas', () {
    final groupes = regrouperReactions([
      (expediteur: lea, symbole: '👍', retiree: true),
      (expediteur: hugo, symbole: null, retiree: false),
      (expediteur: hugo, symbole: '', retiree: false),
    ], moi);
    expect(groupes, isEmpty);
  });

  test('la même personne avec le même symbole ne compte qu une fois', () {
    final groupes = regrouperReactions([
      (expediteur: lea, symbole: '✅', retiree: false),
      (expediteur: lea, symbole: '✅', retiree: false),
    ], moi);
    expect(groupes.single.expediteurs, [lea]);
  });

  test('la règle de push ne vise que les réactions à mes messages, avec son',
      () {
    final regle = corpsRegleReactions(moi);
    expect(regle['conditions'], [
      {'kind': 'event_match', 'key': 'type', 'pattern': 'm.reaction'},
      {
        'kind': 'im.nheko.msc3664.related_event_match',
        'rel_type': 'm.annotation',
        'key': 'sender',
        'pattern': moi,
      },
    ]);
    // Sans son, Synapse pousse en priorité basse et Android retarde l'avis.
    expect(regle['actions'], [
      'notify',
      {'set_tweak': 'sound', 'value': 'default'},
    ]);
  });

  group('réactions de mes bots, tues par le serveur', () {
    const sindri = '@sindri:r';
    const saga = '@saga:r';

    test('une règle muette par bot, sans notification', () {
      final corps = corpsRegleBot(sindri);
      expect(corps['actions'], isEmpty);
      // Il voyage dans l'adresse : rien qui puisse revenir encodé.
      expect(regleBot('@sindri:rempart-messenger.fr'), isNot(contains('@')));
      expect(regleBot('@sindri:rempart-messenger.fr'), isNot(contains(':')));
      expect(corps['conditions'], [
        {'kind': 'event_match', 'key': 'type', 'pattern': 'm.reaction'},
        {'kind': 'event_match', 'key': 'sender', 'pattern': sindri},
      ]);
    });

    test('première fois : tout se pose, la règle de réaction d abord', () {
      final plan = planReglesReactions(override: [], bots: {sindri, saga});
      expect(plan.reposerReactions, isTrue);
      expect(plan.placer, unorderedEquals([sindri, saga]));
      expect(plan.retirer, isEmpty);
    });

    test('déjà en place, au-dessus de la règle de réaction : rien à faire', () {
      final plan = planReglesReactions(
        override: [regleBot(sindri), regleBot(saga), regleReactions],
        bots: {sindri, saga},
      );
      expect(plan.reposerReactions, isFalse);
      expect(plan.placer, isEmpty);
      expect(plan.retirer, isEmpty);
    });

    test('une règle de bot passée SOUS la règle de réaction est replacée', () {
      // Synapse évalue dans l ordre : en dessous, elle ne tait plus rien.
      final plan = planReglesReactions(
        override: [regleBot(sindri), regleReactions, regleBot(saga)],
        bots: {sindri, saga},
      );
      expect(plan.placer, [saga]);
    });

    test('règle de réaction absente : reposée, et tous les bots replacés', () {
      // Reposée, elle remonte en tête et passerait devant eux.
      final plan = planReglesReactions(
        override: [regleBot(sindri)],
        bots: {sindri},
      );
      expect(plan.reposerReactions, isTrue);
      expect(plan.placer, [sindri]);
    });

    test('un bot qui n est plus à moi retrouve ses notifications', () {
      // Un nom de bot supprimé peut être repris par quelqu un d autre.
      final plan = planReglesReactions(
        override: [regleBot(sindri), regleBot('@ancien_bot:r'), regleReactions],
        bots: {sindri},
      );
      expect(plan.retirer, [regleBot('@ancien_bot:r')]);
    });

    test('liste des bots inconnue : on ne pose ni ne retire rien', () {
      final plan = planReglesReactions(
        override: [regleBot(sindri), regleReactions],
        bots: null,
      );
      expect(plan.placer, isEmpty);
      expect(plan.retirer, isEmpty);
    });
  });
}
