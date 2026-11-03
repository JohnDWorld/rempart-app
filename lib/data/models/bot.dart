/// Une commande proposée par un bot (style Telegram).
class BotCommand {
  const BotCommand(this.commande, this.description);

  /// La commande, préfixe « / » inclus (ex. `/ping`).
  final String commande;

  /// Ce que fait la commande.
  final String description;
}
