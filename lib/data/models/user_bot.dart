import 'bot.dart';

/// Un bot créé par l'utilisateur, piloté par son agent externe via la gateway.
///
/// Le bot est un compte Matrix hébergé côté serveur (sa credential ne quitte
/// jamais le serveur). L'utilisateur ne détient qu'un token révocable, remis à
/// la création (voir [CreatedBot]).
class UserBot {
  const UserBot({
    required this.botId,
    required this.mxid,
    required this.name,
    this.description = '',
    this.commands = const <BotCommand>[],
    this.avatarUrl = '',
    this.isPublic = false,
    this.managed = false,
    this.moderationReason = '',
    this.createdAt,
  });

  factory UserBot.fromJson(Map<String, dynamic> json) => UserBot(
        botId: json['bot_id'] as String,
        mxid: json['mxid'] as String,
        name: (json['name'] as String?) ?? '',
        description: (json['description'] as String?) ?? '',
        commands: _parseCommands(json['commands']),
        avatarUrl: (json['avatar_url'] as String?) ?? '',
        isPublic: (json['public'] as bool?) ?? false,
        managed: (json['managed'] as bool?) ?? false,
        moderationReason: (json['moderation_reason'] as String?) ?? '',
        createdAt: json['created_at'] as int?,
      );

  /// Identifiant interne du bot.
  final String botId;

  /// Identifiant Matrix du bot (`@ubot_...:domaine`).
  final String mxid;

  /// Nom affiché du bot.
  final String name;

  /// Description libre du bot (config riche).
  final String description;

  /// Commandes déclarées du bot (façon `/setcommands`).
  final List<BotCommand> commands;

  /// Avatar du bot au format mxc (`mxc://...`), vide si non défini.
  final String avatarUrl;

  /// Bot visible dans l'annuaire public (opt-in du propriétaire).
  final bool isPublic;

  /// Agent livré par la boutique : le bot appartient à l'utilisateur, mais
  /// c'est Rempart qui le fait tourner et qui détient son token. Régénérer ce
  /// token couperait l'agent sans rien apporter, d'où l'action masquée.
  final bool managed;

  /// Motif de dépublication par la modération, vide si le bot est sain. Tant
  /// qu'il est non vide, le bot ne peut pas être republié sans être modifié.
  final String moderationReason;

  /// Date de création (epoch secondes), si fournie.
  final int? createdAt;
}

/// Parse la liste de commandes renvoyée par la gateway (`[{command, description}]`).
List<BotCommand> _parseCommands(dynamic raw) =>
    ((raw as List<dynamic>?) ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(
          (c) => BotCommand(
            (c['command'] as String?) ?? '',
            (c['description'] as String?) ?? '',
          ),
        )
        .toList();

/// Entrée d'annuaire : un bot public vu par les autres utilisateurs.
///
/// Anonyme par conception : ni identifiant interne, ni propriétaire. On n'a que
/// de quoi présenter le bot et lancer une conversation (son mxid).
class DirectoryBot {
  const DirectoryBot({
    required this.mxid,
    required this.name,
    this.description = '',
    this.commands = const <BotCommand>[],
    this.avatarUrl = '',
  });

  factory DirectoryBot.fromJson(Map<String, dynamic> json) => DirectoryBot(
        mxid: json['mxid'] as String,
        name: (json['name'] as String?) ?? '',
        description: (json['description'] as String?) ?? '',
        commands: _parseCommands(json['commands']),
        avatarUrl: (json['avatar_url'] as String?) ?? '',
      );

  final String mxid;
  final String name;
  final String description;
  final List<BotCommand> commands;
  final String avatarUrl;
}

/// Quota de bots d'un utilisateur : nombre créés et plafond serveur.
///
/// Le plafond est appliqué côté gateway (refus 429 sur createBot). L'exposer
/// permet à l'app d'afficher "X / N" et de griser la création avant le refus.
class BotQuota {
  const BotQuota({required this.used, required this.limit});

  factory BotQuota.fromJson(Map<String, dynamic> json) => BotQuota(
        used: (json['used'] as num?)?.toInt() ?? 0,
        limit: (json['limit'] as num?)?.toInt() ?? 0,
      );

  final int used;

  /// Nombre de bots autorisés, `0` pour « sans plafond ».
  ///
  /// La gateway renvoie `null` pour les comptes qu'elle dispense de quota, ce
  /// que `fromJson` ramène à 0 : la création reste ouverte et l'écran affiche
  /// le seul décompte, sans le « / N » qui n'aurait rien à dire.
  final int limit;

  /// Plafond atteint : la création doit être bloquée.
  bool get isFull => limit > 0 && used >= limit;
}

/// Liste des bots de l'utilisateur, accompagnée de son quota.
class MyBotsList {
  const MyBotsList({required this.bots, this.quota});

  final List<UserBot> bots;

  /// Quota renvoyé par la gateway, ou null si une version antérieure ne
  /// l'expose pas (l'UI masque alors l'indicateur).
  final BotQuota? quota;
}

/// Résultat de la création d'un bot : inclut le token d'API, affiché UNE fois.
class CreatedBot {
  const CreatedBot({
    required this.botId,
    required this.mxid,
    required this.name,
    required this.apiToken,
  });

  factory CreatedBot.fromJson(Map<String, dynamic> json) => CreatedBot(
        botId: json['bot_id'] as String,
        mxid: json['mxid'] as String,
        name: (json['name'] as String?) ?? '',
        apiToken: json['api_token'] as String,
      );

  final String botId;
  final String mxid;
  final String name;

  /// Token d'API révocable à donner à l'agent externe. Non stocké côté app.
  final String apiToken;
}
