import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/user_bot.dart';
import '../../../data/providers/providers.dart';
import '../../widgets/adaptive/adaptive.dart';

/// Annuaire des bots publics : découvrir les bots que d'autres utilisateurs ont
/// rendus publics, et lancer une conversation.
///
/// Comme tout chat bot, la conversation est NON chiffrée (le bot lit les
/// messages pour répondre). L'annuaire est anonyme : on ne voit jamais qui a
/// créé un bot.
class BotDirectoryScreen extends ConsumerStatefulWidget {
  const BotDirectoryScreen({super.key});

  @override
  ConsumerState<BotDirectoryScreen> createState() => _BotDirectoryScreenState();
}

class _BotDirectoryScreenState extends ConsumerState<BotDirectoryScreen> {
  final _searchController = TextEditingController();
  late Future<List<DirectoryBot>> _future;
  bool _starting = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<List<DirectoryBot>> _load() {
    return ref
        .read(botGatewayServiceProvider)
        .directory(query: _searchController.text);
  }

  void _refresh() {
    setState(() => _future = _load());
  }

  void _onSearchChanged(String _) {
    // Anti-rebond : on ne requête pas à chaque frappe.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _refresh);
  }

  Future<void> _reportBot(DirectoryBot bot) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Signaler ${bot.name.isEmpty ? "ce bot" : bot.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Votre signalement est envoyé à la modération. Au-delà d'un "
              'certain nombre, un administrateur examine le bot.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Motif (facultatif)',
                hintText: 'Ex. contenu abusif, spam...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Signaler'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await ref
          .read(botGatewayServiceProvider)
          .reportBot(bot.mxid, controller.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signalement envoyé. Merci.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Échec du signalement : $e')),
        );
      }
    }
  }

  Future<void> _startChat(DirectoryBot bot) async {
    setState(() => _starting = true);
    try {
      final matrixService = ref.read(matrixServiceProvider);
      // Chiffré si ce bot tient ses propres clés, en clair sinon : même
      // règle que le catalogue.
      final roomId = await matrixService.createDirectChat(
        bot.mxid,
        encrypted: await matrixService.saitDechiffrer(bot.mxid),
      );
      // Accueil best-effort : /start une fois le bot présent dans la room.
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
        setState(() => _starting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AdaptiveScaffold(
      title: 'Découvrir des bots',
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _refresh(),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Rechercher un bot',
                    border: const OutlineInputBorder(),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _refresh();
                            },
                          ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Bots rendus publics par leurs créateurs. Les conversations '
                    'ne sont pas chiffrées.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: FutureBuilder<List<DirectoryBot>>(
                    future: _future,
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
                      final bots = snapshot.data ?? const <DirectoryBot>[];
                      if (bots.isEmpty) {
                        return _EmptyView(
                          searching: _searchController.text.trim().isNotEmpty,
                        );
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: bots.length,
                        itemBuilder: (context, i) => _DirectoryTile(
                          bot: bots[i],
                          onTap: _starting ? null : () => _startChat(bots[i]),
                          onReport:
                              _starting ? null : () => _reportBot(bots[i]),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
          if (_starting)
            const ColoredBox(
              color: Color(0x66000000),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class _DirectoryTile extends StatelessWidget {
  const _DirectoryTile({
    required this.bot,
    required this.onTap,
    required this.onReport,
  });

  final DirectoryBot bot;
  final VoidCallback? onTap;
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: onTap,
        isThreeLine: bot.description.isNotEmpty,
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child:
              Icon(Icons.smart_toy_outlined, color: theme.colorScheme.primary),
        ),
        title: Text(bot.name.isEmpty ? 'Bot sans nom' : bot.name),
        subtitle: Text(
          bot.description.isEmpty ? 'Aucune description' : bot.description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        trailing: PopupMenuButton<String>(
          icon: Icon(Icons.adaptive.more),
          tooltip: 'Actions',
          onSelected: (value) {
            if (value == 'chat') {
              onTap?.call();
            } else if (value == 'report') {
              onReport?.call();
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem<String>(
              value: 'chat',
              child: ListTile(
                leading: Icon(Icons.chat_bubble_outline),
                title: Text('Discuter'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem<String>(
              value: 'report',
              child: ListTile(
                leading: Icon(Icons.flag_outlined),
                title: Text('Signaler'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 96),
        Icon(
          searching ? Icons.search_off : Icons.smart_toy_outlined,
          size: 48,
          color: Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            searching
                ? 'Aucun bot ne correspond.'
                : 'Aucun bot public pour le moment.',
          ),
        ),
      ],
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
