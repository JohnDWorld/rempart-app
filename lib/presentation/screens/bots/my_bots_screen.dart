import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/bot_gateway_constants.dart';
import '../../../data/models/bot.dart';
import '../../../data/models/user_bot.dart';
import '../../../data/providers/providers.dart';
import '../../widgets/adaptive/adaptive.dart';

/// Écran "Mes bots" : créer et gérer ses propres bots (à la BotFather).
///
/// Un bot créé ici est hébergé côté serveur ; l'utilisateur reçoit un token
/// révocable qu'il branche sur son agent externe (voir la Bot Gateway).
class MyBotsScreen extends ConsumerStatefulWidget {
  const MyBotsScreen({super.key});

  @override
  ConsumerState<MyBotsScreen> createState() => _MyBotsScreenState();
}

class _MyBotsScreenState extends ConsumerState<MyBotsScreen> {
  late Future<MyBotsList> _botsFuture;
  bool _busy = false;

  /// Dernier quota connu, pour désactiver le FAB "Créer" hors du FutureBuilder.
  BotQuota? _quota;

  @override
  void initState() {
    super.initState();
    _botsFuture = _load();
  }

  Future<MyBotsList> _load() {
    return ref.read(botGatewayServiceProvider).myBots();
  }

  void _refresh() {
    setState(() {
      _botsFuture = _load();
    });
  }

  Future<void> _createBot() async {
    // Garde-fou : le serveur refuse (429) au-delà du quota, on l'anticipe pour
    // ne pas demander un nom en vain.
    final quota = _quota;
    if (quota != null && quota.isFull) {
      _snack('Limite atteinte : ${quota.limit} bots maximum.');
      return;
    }
    final saisie = await _askName();
    if (saisie == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      final created = await ref
          .read(botGatewayServiceProvider)
          .createBot(saisie.nom, username: saisie.username);
      if (mounted) {
        await _showToken(created);
        _refresh();
      }
    } catch (e) {
      _snack('Échec de la création : $e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _regenerateToken(UserBot bot) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Régénérer le token ?'),
        content: Text(
          "L'ancien token de ${bot.name} cessera immédiatement de fonctionner. "
          'Mettez à jour votre agent avec le nouveau. Le bot et ses '
          'conversations sont conservés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Régénérer'),
          ),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    setState(() => _busy = true);
    try {
      final created =
          await ref.read(botGatewayServiceProvider).regenerateToken(bot.botId);
      if (mounted) {
        await _showToken(created, title: 'Nouveau token');
      }
    } catch (e) {
      _snack('Échec de la régénération : $e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// Met l'adresse Matrix du bot dans le presse-papier.
  ///
  /// C'est ce qu'on donne à un agent ou ce qu'on colle pour inviter le bot
  /// dans un groupe : l'information reste à portée, sans encombrer la fiche
  /// d'une suite de caractères que personne ne lit.
  Future<void> _copierAdresse(UserBot bot) async {
    await Clipboard.setData(ClipboardData(text: bot.mxid));
    _snack('Adresse de ${bot.name} copiée');
  }

  Future<void> _configureBot(UserBot bot) async {
    final result = await showDialog<_BotConfigResult>(
      context: context,
      builder: (context) => _BotConfigDialog(bot: bot),
    );
    if (result == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      final service = ref.read(botGatewayServiceProvider);
      await service.setBotConfig(
        bot.botId,
        name: result.name,
        description: result.description,
        commands: result.commands,
      );
      if (result.avatarUrl.isNotEmpty) {
        await service.setBotAvatar(bot.botId, result.avatarUrl);
      }
      _snack('Configuration enregistrée.');
      _refresh();
    } catch (e) {
      _snack('Échec de la configuration : $e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _toggleVisibility(UserBot bot) async {
    // Bot sous verrou de modération : republication refusée tant qu'il n'est pas
    // modifié. On l'explique sans aller au refus serveur.
    if (!bot.isPublic && bot.moderationReason.isNotEmpty) {
      _snack('Modifiez ce bot (Configurer) pour pouvoir le republier.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(botGatewayServiceProvider)
          .setBotVisibility(bot.botId, isPublic: !bot.isPublic);
      _snack(
        bot.isPublic
            ? '${bot.name} est de nouveau privé.'
            : "${bot.name} est visible dans l'annuaire.",
      );
      _refresh();
    } catch (e) {
      _snack('Échec du changement de visibilité : $e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// Ouvre la conversation avec son propre bot.
  ///
  /// Le seul moyen de vérifier qu'un agent répond : sans cela, le bot n'est
  /// joignable que par l'annuaire, et uniquement s'il a été rendu public.
  Future<void> _ouvrirChat(UserBot bot) async {
    setState(() => _busy = true);
    try {
      // Chiffrée si ce bot tient ses propres clés. Un bot piloté par la
      // passerelle n'en a pas : son fil reste en clair, faute de quoi il ne
      // lirait rien. Même règle que le catalogue.
      final matrixService = ref.read(matrixServiceProvider);
      final roomId = await matrixService.createDirectChat(
        bot.mxid,
        encrypted: await matrixService.saitDechiffrer(bot.mxid),
      );
      if (mounted) {
        context.pushReplacement('/chat/$roomId');
      }
    } catch (e) {
      _snack("Impossible d'ouvrir la conversation : $e");
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _confirmDelete(UserBot bot) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer le bot ?'),
        content: Text(
          'Le bot ${bot.name} sera révoqué et cessera de répondre. '
          'Cette action est définitive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(botGatewayServiceProvider).deleteBot(bot.botId);
      _refresh();
    } catch (e) {
      _snack('Échec de la suppression : $e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<({String nom, String username})?> _askName() {
    return showDialog<({String nom, String username})>(
      context: context,
      builder: (context) => const _DialogueNouveauBot(),
    );
  }

  Future<void> _showToken(CreatedBot bot, {String title = 'Bot créé'}) {
    final messenger = ScaffoldMessenger.of(context);
    final theme = Theme.of(context);
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(bot.name, style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            const Text(
              "Token d'API (affiché une seule fois). Donnez-le à votre agent, "
              'jamais à un tiers. Perdu ou compromis : régénérez-le depuis le '
              'menu du bot.',
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                bot.apiToken,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
            // Un token sans l'adresse a laquelle le presenter ne sert a rien :
            // la personne repart avec un secret et aucune idee de ce qu'elle
            // doit appeler. Les trois voies sont nommees parce qu'elles ne se
            // devinent pas, et que le webhook evite d'ecrire une boucle
            // d'attente a ceux qui ont deja un serveur.
            if (BotGatewayConstants.baseUrl.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Où le présenter', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              SelectableText(
                BotGatewayConstants.baseUrl,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              const SizedBox(height: 8),
              Text(
                'En-tête « Authorization: Bearer <token> ». Trois façons de '
                'brancher votre agent :\n'
                '· /v1/getUpdates, vous relevez les messages ;\n'
                '· /v1/setWebhook, Rempart les pousse chez vous ;\n'
                '· /mcp, pour un client MCP, sans rien écrire.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: bot.apiToken));
              messenger.showSnackBar(
                const SnackBar(content: Text('Token copié')),
              );
            },
            child: const Text('Copier'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("J'ai noté"),
          ),
        ],
      ),
    );
  }

  void _snack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final quotaFull = _quota?.isFull ?? false;
    return AdaptiveScaffold(
      title: 'Mes bots',
      floatingActionButton: FloatingActionButton(
        onPressed: (_busy || quotaFull) ? null : _createBot,
        backgroundColor: quotaFull
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : null,
        // Le compteur de quota juste au-dessus dit déjà « n / 10 bots » :
        // écrire « Limite atteinte » sur le bouton le répétait, et l'étiquette
        // débordait de la pastille.
        tooltip: quotaFull ? 'Limite de bots atteinte' : 'Créer un bot',
        child: const Icon(Icons.add),
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: FutureBuilder<MyBotsList>(
              future: _botsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _ErrorView(
                    message: '${snapshot.error}',
                    onRetry: _refresh,
                  );
                }
                final bots = snapshot.data?.bots ?? const <UserBot>[];
                final quota = snapshot.data?.quota;
                // Mémorise le quota pour l'état du FAB (hors de ce builder).
                // Post-frame pour ne pas appeler setState pendant le build ;
                // comparaison par valeur pour ne pas reboucler.
                if (quota != null &&
                    (quota.used != _quota?.used ||
                        quota.limit != _quota?.limit)) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _quota = quota);
                  });
                }
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Créez un bot piloté par VOTRE agent externe. Le bot est '
                      'hébergé par Rempart ; vous recevez un token pour brancher '
                      'votre agent. Conversations non chiffrées.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                    if (quota != null) ...[
                      const SizedBox(height: 12),
                      _QuotaIndicator(quota: quota),
                    ],
                    const SizedBox(height: 16),
                    if (bots.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: Text('Aucun bot pour le moment.'),
                        ),
                      )
                    else
                      for (final bot in bots)
                        _BotTile(
                          onOuvrirChat: _busy ? null : () => _ouvrirChat(bot),
                          onCopierAdresse:
                              _busy ? null : () => _copierAdresse(bot),
                          bot: bot,
                          onConfigure: _busy ? null : () => _configureBot(bot),
                          onRegenerate:
                              _busy ? null : () => _regenerateToken(bot),
                          onToggleVisibility:
                              _busy ? null : () => _toggleVisibility(bot),
                          onDelete: _busy ? null : () => _confirmDelete(bot),
                        ),
                    const SizedBox(height: 8),
                    const _CarteBoutique(),
                  ],
                );
              },
            ),
          ),
          if (_busy)
            const ColoredBox(
              color: Color(0x66000000),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

/// Indicateur de quota : "X / N bots", avec un ton d'alerte à la limite.
class _QuotaIndicator extends StatelessWidget {
  const _QuotaIndicator({required this.quota});

  final BotQuota quota;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final full = quota.isFull;
    final color = full ? theme.colorScheme.error : theme.colorScheme.outline;
    return Row(
      children: [
        Icon(
          full ? Icons.block : Icons.smart_toy_outlined,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 6),
        Text(
          quota.limit > 0
              ? '${quota.used} / ${quota.limit} bots'
              : '${quota.used} bot${quota.used > 1 ? 's' : ''}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (full) ...[
          const SizedBox(width: 6),
          Text(
            '· limite atteinte',
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ],
      ],
    );
  }
}

class _BotTile extends StatelessWidget {
  const _BotTile({
    required this.bot,
    required this.onOuvrirChat,
    required this.onCopierAdresse,
    required this.onConfigure,
    required this.onRegenerate,
    required this.onToggleVisibility,
    required this.onDelete,
  });

  final UserBot bot;
  final VoidCallback? onOuvrirChat;
  final VoidCallback? onCopierAdresse;
  final VoidCallback? onConfigure;
  final VoidCallback? onRegenerate;
  final VoidCallback? onToggleVisibility;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onOuvrirChat != null ||
        onCopierAdresse != null ||
        onConfigure != null ||
        onRegenerate != null ||
        onToggleVisibility != null ||
        onDelete != null;
    // L'adresse du bot passe par « Copier l'adresse » : affichée ici, elle
    // prenait la place de la description sans rien dire de ce que le bot fait.
    final subtitle = bot.description.isEmpty
        ? 'Aucune description'
        : bot.description;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          if (bot.moderationReason.isNotEmpty)
            _ModerationBanner(reason: bot.moderationReason),
          ListTile(
            isThreeLine: bot.description.isNotEmpty,
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(Icons.smart_toy_outlined,
                  color: theme.colorScheme.primary),
            ),
            title: Row(
              children: [
                Flexible(
                    child: Text(bot.name, overflow: TextOverflow.ellipsis)),
                if (bot.managed) ...[
                  const SizedBox(width: 8),
                  const _Pastille(
                    icone: Icons.verified_outlined,
                    texte: 'Rempart',
                  ),
                ],
                if (bot.isPublic) ...[
                  const SizedBox(width: 8),
                  const _Pastille(icone: Icons.public, texte: 'Public'),
                ],
              ],
            ),
            subtitle: Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            trailing: PopupMenuButton<String>(
              enabled: enabled,
              icon: Icon(Icons.adaptive.more),
              tooltip: 'Actions',
              onSelected: (value) {
                if (value == 'chat') {
                  onOuvrirChat?.call();
                } else if (value == 'adresse') {
                  onCopierAdresse?.call();
                } else if (value == 'configure') {
                  onConfigure?.call();
                } else if (value == 'regenerate') {
                  onRegenerate?.call();
                } else if (value == 'visibility') {
                  onToggleVisibility?.call();
                } else if (value == 'delete') {
                  onDelete?.call();
                }
              },
              itemBuilder: (context) => [
                // En tête : c'est l'action qu'on vient chercher le plus souvent,
                // parler à son bot pour vérifier que l'agent répond bien.
                const PopupMenuItem<String>(
                  value: 'chat',
                  child: ListTile(
                    leading: Icon(Icons.chat_bubble_outline),
                    title: Text('Ouvrir la conversation'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'adresse',
                  child: ListTile(
                    leading: Icon(Icons.alternate_email),
                    title: Text("Copier l'adresse du bot"),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'configure',
                  child: ListTile(
                    leading: Icon(Icons.tune),
                    title: Text('Configurer'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                // Un agent livré n'est pas publiable : son persona est le
                // produit de la boutique, et l'ouvrir à l'annuaire ferait
                // répondre l'agent d'un client à tout le monde, aux frais de
                // l'exploitant qui l'héberge.
                if (!bot.managed)
                  PopupMenuItem<String>(
                    value: 'visibility',
                    child: ListTile(
                      leading: Icon(
                        bot.isPublic ? Icons.lock_outline : Icons.public,
                      ),
                      title: Text(
                        bot.isPublic ? 'Rendre privé' : 'Rendre public',
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                // Le token vit chez l'exploitant, qui fait tourner l'agent :
                // le régénérer couperait le service sans rien apporter.
                if (!bot.managed)
                  const PopupMenuItem<String>(
                    value: 'regenerate',
                    child: ListTile(
                      leading: Icon(Icons.vpn_key_outlined),
                      title: Text('Régénérer le token'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                const PopupMenuItem<String>(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline),
                    title: Text('Supprimer'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bandeau sur un bot retiré de l'annuaire par la modération.
class _ModerationBanner extends StatelessWidget {
  const _ModerationBanner({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.gavel, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Retiré de l'annuaire par la modération.\nMotif : $reason\n"
              'Modifiez ce bot (Configurer) pour pouvoir le republier.',
              style: TextStyle(color: scheme.onErrorContainer, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Petit badge posé à côté du nom d'un bot : « Public » dans l'annuaire,
/// « Rempart » pour un agent livré par la boutique.
class _Pastille extends StatelessWidget {
  const _Pastille({required this.icone, required this.texte});

  final IconData icone;
  final String texte;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 12, color: scheme.onSecondaryContainer),
          const SizedBox(width: 3),
          Text(
            texte,
            style: TextStyle(fontSize: 11, color: scheme.onSecondaryContainer),
          ),
        ],
      ),
    );
  }
}

/// Vitrine de la boutique, en pied de liste.
///
/// Elle vaut autant pour qui n'a aucun bot que pour qui en a déjà : écrire un
/// agent et en commander un ne s'adressent pas au même besoin. C'est aussi le
/// seul endroit visible, le menu principal ouvrant « Mes bots » directement
/// plutôt que l'onglet Bots.
class _CarteBoutique extends StatelessWidget {
  const _CarteBoutique();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              "Pas d'agent à brancher ?",
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              "Nous pouvons le construire et l'héberger pour vous. "
              'Il apparaîtra ici, prêt à répondre.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => context.push('/boutique-agents'),
              icon: const Icon(Icons.storefront),
              label: const Text('Boutique à agents'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 64),
        Icon(
          Icons.error_outline,
          size: 48,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(height: 16),
        Center(child: Text(message, textAlign: TextAlign.center)),
        const SizedBox(height: 16),
        Center(
          child:
              FilledButton(onPressed: onRetry, child: const Text('Réessayer')),
        ),
      ],
    );
  }
}

/// Résultat de l'édition de config d'un bot.
class _BotConfigResult {
  const _BotConfigResult({
    required this.name,
    required this.description,
    required this.commands,
    required this.avatarUrl,
  });

  final String name;
  final String description;
  final List<BotCommand> commands;
  final String avatarUrl;
}

/// Dialogue d'édition de la config riche d'un bot : nom, description,
/// commandes déclarées (une par ligne, `commande - description`) et avatar
/// (URL d'image, publiée côté serveur sur le compte Matrix du bot).
class _BotConfigDialog extends StatefulWidget {
  const _BotConfigDialog({required this.bot});

  final UserBot bot;

  @override
  State<_BotConfigDialog> createState() => _BotConfigDialogState();
}

class _BotConfigDialogState extends State<_BotConfigDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _commands;
  late final TextEditingController _avatar;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.bot.name);
    _description = TextEditingController(text: widget.bot.description);
    _commands = TextEditingController(
      text: widget.bot.commands
          .map(
            (c) => c.description.isEmpty
                ? c.commande
                : '${c.commande} - ${c.description}',
          )
          .join('\n'),
    );
    _avatar = TextEditingController();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _commands.dispose();
    _avatar.dispose();
    super.dispose();
  }

  List<BotCommand> _parseCommands(String text) {
    final out = <BotCommand>[];
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) {
        continue;
      }
      final idx = line.indexOf(' - ');
      if (idx >= 0) {
        out.add(
          BotCommand(
            line.substring(0, idx).trim(),
            line.substring(idx + 3).trim(),
          ),
        );
      } else {
        out.add(BotCommand(line, ''));
      }
    }
    return out;
  }

  void _save() {
    Navigator.pop(
      context,
      _BotConfigResult(
        name: _name.text.trim(),
        description: _description.text.trim(),
        commands: _parseCommands(_commands.text),
        avatarUrl: _avatar.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Configurer le bot'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nom'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Description',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _commands,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Commandes',
                hintText: "/meteo - météo du jour\n/aide - obtenir de l'aide",
                alignLabelWithHint: true,
                helperText: 'Une par ligne : commande - description',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _avatar,
              decoration: const InputDecoration(
                labelText: "Avatar (URL d'image)",
                hintText: 'https://...',
                helperText: 'Laisser vide pour ne pas changer',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        TextButton(onPressed: _save, child: const Text('Enregistrer')),
      ],
    );
  }
}

/// Dialogue de création d'un bot : nom réel puis nom affiché.
///
/// Le nom réel devient le localpart Matrix (`@agent_bot:domaine`) et ne pourra
/// plus changer, un localpart Matrix étant immuable. On le valide donc avant
/// l'envoi, avec les mêmes règles que la gateway, pour éviter un aller-retour
/// réseau sur une faute de frappe. Le serveur reste l'autorité, notamment sur
/// l'unicité qu'on ne peut pas vérifier ici.
class _DialogueNouveauBot extends StatefulWidget {
  const _DialogueNouveauBot();

  @override
  State<_DialogueNouveauBot> createState() => _DialogueNouveauBotState();
}

class _DialogueNouveauBotState extends State<_DialogueNouveauBot> {
  static final _formeValide = RegExp(r'^[a-z0-9][a-z0-9_]*bot$');
  static const _prefixesReserves = ['rempart_', 'u_'];
  static const _longueurMin = 5;
  static const _longueurMax = 32;

  final _usernameController = TextEditingController();
  final _nomController = TextEditingController();
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _usernameController.addListener(_valider);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _nomController.dispose();
    super.dispose();
  }

  /// Renvoie le message d'erreur, ou null si le nom est acceptable.
  String? _controler(String saisie) {
    final candidat = saisie.trim().toLowerCase();
    if (candidat.isEmpty) return null; // Rien tapé : pas encore d'erreur.
    if (!candidat.endsWith('bot')) {
      return 'Doit se terminer par « bot »';
    }
    if (candidat.length < _longueurMin || candidat.length > _longueurMax) {
      return 'Entre $_longueurMin et $_longueurMax caractères';
    }
    if (!_formeValide.hasMatch(candidat)) {
      return 'Lettres non accentuées, chiffres et « _ » seulement';
    }
    if (_prefixesReserves.any(candidat.startsWith)) {
      return 'Ce préfixe est réservé';
    }
    return null;
  }

  void _valider() {
    final erreur = _controler(_usernameController.text);
    if (erreur != _erreur) {
      setState(() => _erreur = erreur);
    } else {
      // Le bouton dépend aussi du contenu, pas seulement de l'erreur.
      setState(() {});
    }
  }

  bool get _peutCreer {
    final candidat = _usernameController.text.trim();
    return candidat.isNotEmpty && _controler(candidat) == null;
  }

  void _creer() {
    if (!_peutCreer) return;
    final username = _usernameController.text.trim().toLowerCase();
    final nom = _nomController.text.trim();
    Navigator.pop(
      context,
      (nom: nom.isEmpty ? username : nom, username: username),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouveau bot'),
      // Défilable : clavier ouvert, le dialogue n'a plus la place d'afficher
      // ses deux champs, et ce sont les explications du bas qui disparaissent.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // La règle est AU-DESSUS du champ : en dessous, elle passe sous le
            // clavier, et le message d'erreur la remplace dès la première
            // frappe fautive. L'utilisateur ne saurait jamais qu'un nom de bot
            // doit finir par « bot ».
            Text(
              'Doit finir par « bot » (ex. agent_bot ou agentbot). '
              'Définitif, et toujours en minuscules.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _usernameController,
              autofocus: true,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Nom du bot',
                hintText: 'agent_bot',
                errorText: _erreur,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nomController,
              decoration: const InputDecoration(
                labelText: 'Nom affiché (facultatif)',
                hintText: 'Agent',
                helperText: 'Modifiable à tout moment.',
              ),
              onSubmitted: (_) => _creer(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: _peutCreer ? _creer : null,
          child: const Text('Créer'),
        ),
      ],
    );
  }
}
