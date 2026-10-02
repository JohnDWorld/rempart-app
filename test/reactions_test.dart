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
}
