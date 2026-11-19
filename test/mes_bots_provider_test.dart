import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/data/models/bot.dart';
import 'package:rempart_app/data/models/user_bot.dart';
import 'package:rempart_app/data/providers/providers.dart';

/// Le menu des commandes et l'entrée « Configurer le bot » lisent la même
/// liste, « Mes bots » : les commandes en sont tirées, un bot qui n'en déclare
/// aucune reçoit le minimum que tous comprennent.
void main() {
  test('les commandes viennent de Mes bots, avec un repli par défaut', () async {
    const declare = BotCommand('/new', 'Nouvelle session');
    final conteneur = ProviderContainer(
      overrides: [
        mesBotsProvider.overrideWith(
          (ref) async => {
            '@lagertha:x': const UserBot(
              botId: 'b1',
              mxid: '@lagertha:x',
              name: 'Lagertha',
              commands: [declare],
            ),
            '@muet_bot:x': const UserBot(
              botId: 'b2',
              mxid: '@muet_bot:x',
              name: 'Muet',
            ),
          },
        ),
      ],
    );
    addTearDown(conteneur.dispose);

    final commandes = await conteneur.read(commandesDesBotsProvider.future);

    expect(commandes['@lagertha:x']!.map((c) => c.commande), ['/new']);
    expect(
      commandes['@muet_bot:x']!.map((c) => c.commande),
      ['/start', '/help', '/stop'],
    );
    expect(commandes.containsKey('@u_humain:x'), isFalse);
  });
}
