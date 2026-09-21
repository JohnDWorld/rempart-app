import '../../core/constants/matrix_constants.dart';

/// Une commande proposée par un bot (style Telegram).
class BotCommand {
  const BotCommand(this.commande, this.description);

  /// La commande, préfixe « / » inclus (ex. `/ping`).
  final String commande;

  /// Ce que fait la commande.
  final String description;
}

/// Un bot du catalogue Rempart (style Telegram).
///
/// Les conversations avec un bot sont NON chiffrées : le bot doit lire les
/// messages en clair pour y répondre (voir la décision E2E/bots). L'écran de
/// chat le signale via le bandeau « Non chiffré ».
class Bot {
  const Bot({
    required this.username,
    required this.name,
    required this.description,
    required this.commandes,
  });

  /// Localpart du compte Matrix du bot (ex. `rempart_bot`).
  final String username;

  /// Nom affiché du bot.
  final String name;

  /// Courte description de ce que fait le bot.
  final String description;

  /// Commandes disponibles, pour l'aide et les raccourcis.
  final List<BotCommand> commandes;

  /// Identifiant Matrix complet du bot (`@username:domain`).
  String get matrixId => '@$username:${MatrixConstants.domain}';
}

/// Catalogue des bots disponibles.
///
/// v1 : liste curée en dur. À terme, un annuaire côté serveur.
///
/// `@rempart_assistant` en a été retiré : il n'y aura pas d'assistant IA au
/// lancement. Le proposer supposait un serveur d'inférence joignable en
/// permanence, et surtout un destinataire de plus à déclarer, puisque les
/// messages qui lui sont adressés voyagent en clair. Les bots des utilisateurs
/// (« Mes bots ») ne changent pas : leur agent tourne chez eux.
const List<Bot> botCatalogue = <Bot>[
  Bot(
    username: 'rempart_bot',
    name: 'Bot Rempart',
    description: 'Assistant de démonstration : commandes de base.',
    commandes: <BotCommand>[
      BotCommand('/start', "Message d'accueil et liste des commandes"),
      BotCommand('/help', 'Afficher les commandes disponibles'),
      BotCommand('/ping', 'Vérifier que le bot répond'),
      BotCommand('/echo <texte>', 'Le bot répète votre texte'),
    ],
  ),
];
