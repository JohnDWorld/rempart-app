import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rempart_app/data/services/actions_notification.dart';
import 'package:rempart_app/data/services/notification_service.dart';

/// Ce qu'Android Auto exige pour afficher une messagerie : sans l'un de ces
/// points, il ignore les notifications de Rempart, sans rien dire.
void main() {
  final actions = NotificationService.actionsDeConversation;
  AndroidNotificationAction action(String id) =>
      actions.singleWhere((a) => a.id == id);

  test('« Répondre » recueille un texte, sans ouvrir d écran', () {
    final repondre = action(actionRepondre);
    expect(repondre.semanticAction, SemanticAction.reply);
    expect(repondre.inputs, isNotEmpty);
    expect(repondre.showsUserInterface, isFalse);
  });

  test('« Marquer comme lu » est marqué comme tel, sans ouvrir d écran', () {
    final lu = action(actionLu);
    expect(lu.semanticAction, SemanticAction.markAsRead);
    expect(lu.showsUserInterface, isFalse);
  });
}
