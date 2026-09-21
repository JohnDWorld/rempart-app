import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/data/services/bot_gateway_service.dart';

/// Le message d'une erreur de gateway atterrit directement dans une SnackBar.
/// Il doit rester lisible même quand la réponse ne vient pas de la gateway
/// elle-même (proxy en amont, plantage non rattrapé).
void main() {
  test('garde tel quel un message déjà rédigé', () {
    final e = BotGatewayException(409, 'le nom « hermes_bot » est déjà pris');
    expect(e.toString(), 'le nom « hermes_bot » est déjà pris');
    expect(e.estDejaPris, isTrue);
  });

  test("extrait le champ utile d'une réponse JSON", () {
    final e = BotGatewayException(400, '{"error": "username invalide"}');
    expect(e.toString(), 'username invalide');
  });

  test('dépouille une page HTML de proxy', () {
    final e = BotGatewayException(
      502,
      '<html><head><title>502</title></head><body><h1>Bad Gateway</h1></body></html>',
    );
    expect(e.toString(), isNot(contains('<')));
    expect(e.toString(), contains('Bad Gateway'));
  });

  test("tronque une trace d'appels interminable", () {
    final trace = List.filled(500, 'File "gateway.py", line 42, in handler')
        .join('\n');
    final e = BotGatewayException(500, trace);
    expect(e.toString().length, lessThanOrEqualTo(303));
    expect(e.toString(), endsWith('...'));
  });

  test('corps vide : reste explicite sur le code', () {
    expect(BotGatewayException(503, '   ').toString(), 'erreur 503');
  });
}
