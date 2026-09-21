import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../data/models/bot.dart';
import '../../../data/providers/providers.dart';
import '../../widgets/adaptive/adaptive.dart';

/// Catalogue des bots système, ceux livrés avec Rempart (style Telegram).
///
/// Démarrer une conversation avec un bot crée un chat NON chiffré : le bot doit
/// lire les messages en clair pour y répondre. Le bandeau « Non chiffré » de
/// l'écran de chat le signale à l'utilisateur.
class BotsScreen extends ConsumerStatefulWidget {
  const BotsScreen({super.key});

  @override
  ConsumerState<BotsScreen> createState() => _BotsScreenState();
}

class _BotsScreenState extends ConsumerState<BotsScreen> {
  bool _isLoading = false;

  Future<void> _startBotChat(Bot bot) async {
    setState(() => _isLoading = true);
    try {
      final matrixService = ref.read(matrixServiceProvider);

      // Chiffrée si ce bot-là sait lire, en clair sinon : un bot sans clé
      // dans un salon chiffré ne recevrait que du charabia, et le chiffrement
      // ne se retire jamais une fois posé.
      final roomId = await matrixService.createDirectChat(
        bot.matrixId,
        encrypted: await matrixService.saitDechiffrer(bot.matrixId),
      );

      // Auto-accueil style Telegram : on envoie /start une fois que le bot a
      // eu le temps de rejoindre la room (invitation acceptée en asynchrone).
      // Best-effort : si le timing rate, l'utilisateur voit les commandes dans
      // le catalogue et peut taper /start lui-même.
      unawaited(
        Future<void>.delayed(const Duration(seconds: 3)).then(
          (_) => matrixService.sendTextMessage(roomId, '/start'),
        ),
      );

      if (mounted) {
        context.pushReplacement('/chat/$roomId');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible de démarrer le bot : $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      title: 'Bots système',
      previousPageTitle: 'Bots',
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Les conversations avec un bot ne sont pas chiffrées : '
                'le bot lit vos messages pour y répondre.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
              const SizedBox(height: 16),
              for (final bot in botCatalogue)
                _BotCard(
                  bot: bot,
                  onTap: _isLoading ? null : () => _startBotChat(bot),
                ),
            ],
          ),
          if (_isLoading)
            const ColoredBox(
              color: Color(0x66000000),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

/// Carte d'un bot dans le catalogue : identité, description et commandes.
class _BotCard extends StatelessWidget {
  const _BotCard({required this.bot, required this.onTap});

  final Bot bot;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(
                      Icons.smart_toy_outlined,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(bot.name, style: theme.textTheme.titleMedium),
                        Text(
                          '@${bot.username}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const _NonChiffreChip(),
                ],
              ),
              const SizedBox(height: 12),
              Text(bot.description, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 16),
              Text(
                'COMMANDES',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 6),
              for (final c in bot.commandes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.commande,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          c.description,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Toucher pour démarrer la conversation',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Petit badge « Non chiffré » affiché sur chaque bot.
class _NonChiffreChip extends StatelessWidget {
  const _NonChiffreChip();

  @override
  Widget build(BuildContext context) {
    // L'avertissement qui dit qu'une conversation est lisible par le serveur
    // tombait à 1,97:1 en thème clair : `Colors.orange` sur sa propre teinte.
    // Il doit être le plus lisible de l'écran, pas le moins.
    final couleur = RempartTokens.texteAlerte(Theme.of(context).brightness);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_open, size: 12, color: couleur),
          const SizedBox(width: 4),
          Text(
            'Non chiffré',
            style: TextStyle(fontSize: 11, color: couleur),
          ),
        ],
      ),
    );
  }
}
