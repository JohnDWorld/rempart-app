
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/plateforme.dart';
import '../../../data/models/profile.dart';
import '../../../data/providers/providers.dart';
import '../../widgets/common/user_avatar.dart';

/// Écran pour créer une nouvelle conversation
class NewChatScreen extends ConsumerStatefulWidget {
  const NewChatScreen({super.key});

  @override
  ConsumerState<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends ConsumerState<NewChatScreen> {
  final _searchController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _startConversation(Profile profile) async {
    setState(() => _isLoading = true);

    try {
      final matrixService = ref.read(matrixServiceProvider);

      // Le compte Matrix du contact suit le schéma unifié `u_<uuid Supabase>`,
      // PAS son username de profil (schéma incompatible : `@username` n'existe
      // pas côté Matrix, l'invitation partirait vers un fantôme).
      final matrixUserId = matrixService.matrixUserIdForSupabaseId(profile.id);

      // Créer ou récupérer la conversation directe
      final roomId = await matrixService.createDirectChat(matrixUserId);

      if (mounted) {
        // Naviguer vers le chat - go('/home') dans chat_screen gèrera le retour
        // `pushReplacement` et non `go` : `go` vide la pile, et le geste de
        // retour fermait alors l'application au lieu de ramener a la liste.
        // L'ecran de creation, lui, cede sa place : y revenir n'aurait pas
        // de sens une fois la conversation ouverte.
        context.pushReplacement('/chat/$roomId');
      }
    } catch (e) {
      if (mounted) {
        if (estIOS) {
          await showCupertinoDialog<void>(
            context: context,
            builder: (context) => CupertinoAlertDialog(
              title: const Text('Erreur'),
              content: Text('$e'),
              actions: [
                CupertinoDialogAction(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur: $e')),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final searchQuery = ref.watch(contactSearchQueryProvider);
    final searchResults = ref.watch(profileSearchProvider(searchQuery));

    if (estIOS) {
      return _buildCupertinoScreen(searchQuery, searchResults);
    }
    return _buildMaterialScreen(searchQuery, searchResults);
  }

  Widget _buildCupertinoScreen(
    String searchQuery,
    AsyncValue<List<Profile>> searchResults,
  ) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    final isDark = brightness == Brightness.dark;

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Nouveau message'),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Barre de recherche
            Padding(
              padding: const EdgeInsets.all(16),
              child: CupertinoSearchTextField(
                controller: _searchController,
                autofocus: true,
                placeholder: 'Rechercher un contact...',
                onChanged: (value) {
                  ref.read(contactSearchQueryProvider.notifier).state = value;
                },
                onSuffixTap: () {
                  _searchController.clear();
                  ref.read(contactSearchQueryProvider.notifier).state = '';
                },
              ),
            ),

            // Bouton créer un groupe
            CupertinoListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: CupertinoTheme.of(context)
                      .primaryColor
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  CupertinoIcons.person_2_fill,
                  color: CupertinoTheme.of(context).primaryColor,
                ),
              ),
              title: const Text('Créer un groupe'),
              trailing: const CupertinoListTileChevron(),
              onTap: () {
                context.push('/new-group');
              },
            ),

            // Parler à un bot (conversation non chiffrée)
            CupertinoListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: CupertinoTheme.of(context)
                      .primaryColor
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  CupertinoIcons.chat_bubble_2_fill,
                  color: CupertinoTheme.of(context).primaryColor,
                ),
              ),
              title: const Text('Parler à un bot'),
              subtitle: const Text('Non chiffré'),
              trailing: const CupertinoListTileChevron(),
              onTap: () {
                context.push('/bots');
              },
            ),

            Container(
              height: 1,
              color: isDark
                  ? CupertinoColors.systemGrey6.darkColor
                  : CupertinoColors.systemGrey6,
            ),

            // Résultats de recherche
            Expanded(
              child: _isLoading
                  ? const Center(child: CupertinoActivityIndicator())
                  : searchResults.when(
                      data: (profiles) {
                        if (searchQuery.isEmpty) {
                          return _buildEmptySearch(context);
                        }

                        if (profiles.isEmpty) {
                          return _buildNoResults(context);
                        }

                        return ListView.builder(
                          itemCount: profiles.length,
                          itemBuilder: (context, index) {
                            final profile = profiles[index];
                            return _buildCupertinoProfileTile(profile);
                          },
                        );
                      },
                      loading: () => const Center(
                        child: CupertinoActivityIndicator(),
                      ),
                      error: (error, _) => Center(
                        child: Text('Erreur: $error'),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMaterialScreen(
    String searchQuery,
    AsyncValue<List<Profile>> searchResults,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nouveau message'),
      ),
      body: Column(
        children: [
          // Barre de recherche
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Rechercher un contact...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(contactSearchQueryProvider.notifier).state =
                              '';
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                ref.read(contactSearchQueryProvider.notifier).state = value;
              },
            ),
          ),

          // Bouton créer un groupe
          ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(
                Icons.group_add,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            title: const Text('Créer un groupe'),
            onTap: () {
              context.push('/new-group');
            },
          ),

          // Parler à un bot (conversation non chiffrée)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(
                Icons.smart_toy_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            title: const Text('Parler à un bot'),
            subtitle: const Text('Non chiffré'),
            onTap: () {
              context.push('/bots');
            },
          ),

          const Divider(),

          // Résultats de recherche
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : searchResults.when(
                    data: (profiles) {
                      if (searchQuery.isEmpty) {
                        return _buildEmptySearch(context);
                      }

                      if (profiles.isEmpty) {
                        return _buildNoResults(context);
                      }

                      return ListView.builder(
                        itemCount: profiles.length,
                        itemBuilder: (context, index) {
                          final profile = profiles[index];
                          return _buildMaterialProfileTile(profile);
                        },
                      );
                    },
                    loading: () => const Center(
                      child: CircularProgressIndicator(),
                    ),
                    error: (error, _) => Center(
                      child: Text('Erreur: $error'),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCupertinoProfileTile(Profile profile) {
    return CupertinoListTile(
      leading: UserAvatar(
        name: profile.name,
        imageUrl: profile.avatarUrl,
        size: 44,
        isOnline: profile.isOnline,
      ),
      title: Text(profile.name),
      subtitle: Text('@${profile.username}'),
      trailing: const CupertinoListTileChevron(),
      onTap: () => _startConversation(profile),
    );
  }

  Widget _buildMaterialProfileTile(Profile profile) {
    return ListTile(
      leading: UserAvatar(
        name: profile.name,
        imageUrl: profile.avatarUrl,
        isOnline: profile.isOnline,
      ),
      title: Text(profile.name),
      subtitle: Text('@${profile.username}'),
      onTap: () => _startConversation(profile),
    );
  }

  Widget _buildEmptySearch(BuildContext context) {
    final isIOS = estIOS;
    final brightness = MediaQuery.platformBrightnessOf(context);
    final isDark = brightness == Brightness.dark;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isIOS ? CupertinoIcons.person_badge_plus : Icons.person_search,
            size: 64,
            color: isIOS
                ? CupertinoColors.systemGrey
                : Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'Recherchez un contact',
            style: isIOS
                ? TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color:
                        isDark ? CupertinoColors.white : CupertinoColors.black,
                  )
                : Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            "Entrez un nom ou un nom d'utilisateur",
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: isIOS
                  ? CupertinoColors.systemGrey
                  : Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResults(BuildContext context) {
    final isIOS = estIOS;
    final brightness = MediaQuery.platformBrightnessOf(context);
    final isDark = brightness == Brightness.dark;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isIOS ? CupertinoIcons.search : Icons.search_off,
            size: 64,
            color: isIOS
                ? CupertinoColors.systemGrey
                : Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'Aucun résultat',
            style: isIOS
                ? TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color:
                        isDark ? CupertinoColors.white : CupertinoColors.black,
                  )
                : Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Aucun utilisateur trouvé',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: isIOS
                  ? CupertinoColors.systemGrey
                  : Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
