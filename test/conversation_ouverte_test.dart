import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/data/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Toucher la notification d'une conversation déjà ouverte refait la pile
  // (`go('/home')` puis `push('/chat/…')`) : le nouvel écran s'ouvre AVANT que
  // l'ancien ne se ferme. Vérifié avec GoRouter le 2026-11-25.
  test("l'ancien écran qui se ferme après le nouveau ne libère rien", () {
    final service = NotificationService.instance;
    final ancien = Object();
    final nouveau = Object();

    service
      ..ouvrirConversation('!sindri', ancien)
      ..ouvrirConversation('!sindri', nouveau)
      ..fermerConversation(ancien);
    expect(service.roomOuverte, '!sindri');

    service.fermerConversation(nouveau);
    expect(service.roomOuverte, isNull);
  });

  test("ouvrir une autre conversation n'est pas défait par la première", () {
    final service = NotificationService.instance;
    final premiere = Object();
    final seconde = Object();

    service
      ..ouvrirConversation('!a', premiere)
      ..ouvrirConversation('!b', seconde)
      ..fermerConversation(premiere);
    expect(service.roomOuverte, '!b');
    service.fermerConversation(seconde);
  });
}
