import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/presentation/widgets/common/user_avatar.dart';

/// Initiales des pastilles sans photo.
///
/// Le cas qui a motivé ce test : un nom de groupe qui finit par un emoji
/// (« Week-end à Biarritz 🌊 ») donnait une demi-paire UTF-16, dessinée en
/// losange à point d'interrogation dans la liste des conversations.
void main() {
  test('deux mots : premières lettres du premier et du dernier', () {
    expect(initialesDe('Inès Belkacem'), 'IB');
    expect(initialesDe('Hugo  Martin'), 'HM');
  });

  test("l'emoji final d'un nom n'est pas une initiale", () {
    expect(initialesDe('Week-end à Biarritz 🌊'), 'WB');
    expect(initialesDe('🎉 Anniversaire de Léa'), 'AL');
  });

  test('un seul mot : ses deux premiers graphèmes', () {
    expect(initialesDe('Léa'), 'LÉ');
    expect(initialesDe('élodie'), 'ÉL');
    expect(initialesDe('courses_camille_bot'), 'CO');
    expect(initialesDe('A'), 'A');
  });

  test('un nom sans lettre garde son premier emoji, entier', () {
    expect(initialesDe('🌊'), '🌊');
    expect(initialesDe('👨‍👩‍👧 🏖️'), '👨‍👩‍👧');
  });

  test('un nom vide ne casse rien', () {
    expect(initialesDe(''), '?');
    expect(initialesDe('   '), '?');
  });
}
