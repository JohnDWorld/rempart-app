import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/presentation/widgets/chat/message_riche.dart';

/// Ce qu'un lien de message a le droit d'ouvrir.
///
/// Le `href` d'un message mis en forme vient d'un tiers. Avant le 2026-09-27,
/// tout partait dans `launchUrl`, quel que soit le schéma.
void main() {
  test('http, https, mailto et tel s ouvrent', () {
    expect(lienOuvrable('https://rempart-messenger.fr/'), isTrue);
    expect(lienOuvrable('http://exemple.fr/page'), isTrue);
    expect(lienOuvrable('HTTPS://EXEMPLE.FR'), isTrue);
    expect(lienOuvrable('mailto:contact@exemple.fr'), isTrue);
    expect(lienOuvrable('tel:+33612345678'), isTrue);
  });

  test('les schémas de script, de fichier et d intention sont refusés', () {
    expect(lienOuvrable('javascript:alert(1)'), isFalse);
    expect(lienOuvrable('JavaScript:alert(1)'), isFalse);
    expect(lienOuvrable('file:///sdcard/Download/x'), isFalse);
    expect(lienOuvrable('intent://scan/#Intent;scheme=zxing;end'), isFalse);
    expect(lienOuvrable('data:text/html,<script>1</script>'), isFalse);
    expect(lienOuvrable('whatsapp://send?text=x'), isFalse);
  });

  test('une adresse sans hôte ou sans schéma ne s ouvre pas', () {
    expect(lienOuvrable('https://'), isFalse);
    expect(lienOuvrable('www.exemple.fr'), isFalse);
    expect(lienOuvrable('/chemin/relatif'), isFalse);
    expect(lienOuvrable(''), isFalse);
    expect(lienOuvrable('mailto:'), isFalse);
  });
}
