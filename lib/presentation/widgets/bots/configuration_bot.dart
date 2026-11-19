import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/bot.dart';
import '../../../data/models/user_bot.dart';
import '../../../data/providers/providers.dart';
import '../adaptive/adaptive.dart';

/// Ouvre la configuration d'un bot (nom, description, commandes, avatar) et
/// l'enregistre. Rend vrai si elle a été enregistrée, faux si l'on a annulé ;
/// un refus de la passerelle remonte tel quel, à l'appelant de le dire.
///
/// Partagée par « Mes bots » et par le menu d'une conversation avec le bot,
/// pour que les deux enregistrent de la même façon. La liste des bots est
/// relue ensuite : le menu des commandes de la conversation en dépend.
/// [auDebutEnregistrement] est appelé une fois la fenêtre fermée, quand
/// l'enregistrement commence (pour l'indicateur de « Mes bots »).
Future<bool> configurerBot(
  BuildContext context,
  WidgetRef ref,
  UserBot bot, {
  VoidCallback? auDebutEnregistrement,
}) async {
  final result = await showAdaptiveDialog<_BotConfigResult>(
    context: context,
    builder: (context) => _BotConfigDialog(bot: bot),
  );
  if (result == null) return false;
  auDebutEnregistrement?.call();
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
  ref.invalidate(mesBotsProvider);
  return true;
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
    return DialogueAdaptatif(
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
                helperMaxLines: 3,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _avatar,
              decoration: const InputDecoration(
                labelText: "Avatar (URL d'image)",
                hintText: 'https://...',
                helperText: 'Laisser vide pour ne pas changer',
                helperMaxLines: 3,
              ),
            ),
          ],
        ),
      ),
      actions: [
        ActionDialogue(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        ActionDialogue(principale: true, onPressed: _save, child: const Text('Enregistrer')),
      ],
    );
  }
}
