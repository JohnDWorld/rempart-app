import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/core/constants/push_constants.dart';

/// Le `.env` de production tel qu'il est : l'application Android seule.
const _production = {
  'FCM_API_KEY': 'cle-android',
  'FCM_APP_ID': '1:243168057583:android:abcdef',
  'FCM_SENDER_ID': '243168057583',
  'FCM_PROJECT_ID': 'rempart-messenger',
};

String? Function(String) _lecteur(Map<String, String> env) => (cle) => env[cle];

void main() {
  test('Android garde ses identifiants', () {
    final options = PushConstants.optionsFirebasePour(
      ios: false,
      lire: _lecteur(_production),
    );
    expect(options?.appId, '1:243168057583:android:abcdef');
  });

  test("l'iPhone ne reçoit jamais l'identifiant Android, qui le ferait planter",
      () {
    expect(
      PushConstants.optionsFirebasePour(ios: true, lire: _lecteur(_production)),
      isNull,
    );
  });

  test("l'iPhone prend ses propres identifiants quand ils existent", () {
    final options = PushConstants.optionsFirebasePour(
      ios: true,
      lire: _lecteur({
        ..._production,
        'FCM_API_KEY_IOS': 'cle-ios',
        'FCM_APP_ID_IOS': '1:243168057583:ios:123456',
      }),
    );
    expect(options?.appId, '1:243168057583:ios:123456');
    expect(options?.apiKey, 'cle-ios');
  });

  test('un identifiant Android rangé par erreur sous la clé iOS est refusé', () {
    expect(
      PushConstants.optionsFirebasePour(
        ios: true,
        lire: _lecteur({
          ..._production,
          'FCM_API_KEY_IOS': 'cle',
          'FCM_APP_ID_IOS': '1:243168057583:android:abcdef',
        }),
      ),
      isNull,
    );
  });
}
