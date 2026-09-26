import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/bot.dart';
import '../../../data/models/profile.dart';
import '../../../data/models/user_bot.dart';
import '../../../data/providers/providers.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/common/user_avatar.dart';

/// Création d'un groupe : nom, participants, puis création de la room Matrix.
///
/// Le groupe est privé et chiffré de bout en bout, toujours : le chiffrement
/// d'un salon Matrix ne se retire jamais, il n'y a donc rien à décider ici.
/// Un bot y est le bienvenu s'il tient ses propres clés (voir
/// `MatrixService.saitDechiffrer`), et prévenu sinon.
class NewGroupScreen extends ConsumerStatefulWidget {
  const NewGroupScreen({super.key});

  @override
  ConsumerState<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends ConsumerState<NewGroupScreen> {
  final _nomController = TextEditingController();
  final _rechercheController = TextEditingController();

  /// Participants choisis, indexés par id Supabase pour éviter les doublons.
  final _selection = <String, Profile>{};

  Timer? _debounce;
  String _query = '';
  bool _creation = false;

  /// Bots choisis, indexés par mxid : nom affiché.
  final _botsChoisis = <String, String>{};

  /// Bots de l'utilisateur, chargés une fois (le catalogue, lui, est en dur).
  Future<List<UserBot>>? _mesBots;

  @override
  void initState() {
    super.initState();
    _mesBots = ref
        .read(botGatewayServiceProvider)
        .myBots()
        .then((liste) => liste.bots);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _nomController.dispose();
    _rechercheController.dispose();
    super.dispose();
  }

  void _onRechercheChanged(String value) {
    // Anti-rebond : chaque frappe interrogerait Supabase.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _query = value.trim());
      }
    });
  }

  void _basculer(Profile profile) {
    setState(() {
      if (_selection.containsKey(profile.id)) {
        _selection.remove(profile.id);
      } else {
        _selection[profile.id] = profile;
      }
    });
  }

  Future<void> _creerGroupe() async {
    final nom = _nomController.text.trim();
    // Un groupe peut n'avoir qu'un bot pour compagnie : exiger une personne
    // ici alors que le bouton est actif produisait un clic sans effet.
    if (nom.isEmpty ||
        (_selection.isEmpty && _botsChoisis.isEmpty) ||
        _creation) {
      return;
    }

    setState(() => _creation = true);
    try {
      final matrixService = ref.read(matrixServiceProvider);
      // Les mxid dérivent des id Supabase (schéma unifié `u_<uuid>`), jamais du
      // username du profil : `@username` n'existe pas côté Matrix.
      final invites =
          _selection.keys.map(matrixService.matrixUserIdForSupabaseId).toList();

      final roomId = await matrixService.createGroup(
        name: nom,
        // Les bots partent avec les invitations initiales : sans cela il
        // faudrait créer le groupe puis y revenir pour les ajouter.
        inviteUserIds: [...invites, ..._botsChoisis.keys],
      );

      // La liste des conversations lit le client Matrix hors du graphe Riverpod.
      ref.read(matrixStateNotifierProvider.notifier).state++;

      if (mounted) {
        // `pushReplacement` : voir new_chat_screen. `go` viderait la pile et
        // le retour fermerait l'application.
        context.pushReplacement('/chat/$roomId');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Création du groupe impossible : $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _creation = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resultats = _query.isEmpty
        ? const AsyncValue<List<Profile>>.data(<Profile>[])
        : ref.watch(profileSearchProvider(_query));
    final pretACreer = _nomController.text.trim().isNotEmpty &&
        (_selection.isNotEmpty || _botsChoisis.isNotEmpty);

    return AdaptiveScaffold(
      title: 'Nouveau groupe',
      actions: [
        TextButton(
          onPressed: pretACreer && !_creation ? _creerGroupe : null,
          child: const Text('Créer'),
        ),
      ],
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _nomController,
                  textInputAction: TextInputAction.next,
                  // Le bouton « Créer » dépend du nom : reconstruire à la frappe.
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Nom du groupe',
                    prefixIcon: const Icon(Icons.group),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const ListTile(
                leading: Icon(Icons.lock),
                title: Text('Chiffré de bout en bout'),
                subtitle: Text(
                  'Tous les groupes le sont. Un bot peut y être ajouté à '
                  'condition de posséder ses propres clés.',
                ),
              ),
              if (_selection.isNotEmpty || _botsChoisis.isNotEmpty)
                SizedBox(
                  height: 56,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final bot in _botsChoisis.entries)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Chip(
                            avatar: const CircleAvatar(
                              child: Icon(Icons.smart_toy_outlined, size: 16),
                            ),
                            label: Text(bot.value),
                            onDeleted: () =>
                                setState(() => _botsChoisis.remove(bot.key)),
                          ),
                        ),
                      for (final profile in _selection.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Chip(
                            avatar: UserAvatar(
                              name: profile.name,
                              imageUrl: profile.avatarUrl,
                              size: 24,
                            ),
                            label: Text(profile.name),
                            onDeleted: () => _basculer(profile),
                          ),
                        ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  controller: _rechercheController,
                  onChanged: _onRechercheChanged,
                  decoration: InputDecoration(
                    hintText: 'Ajouter des participants / bots',
                    prefixIcon: const Icon(Icons.person_add_alt),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              Expanded(child: _buildResultats(resultats, theme)),
            ],
          ),
          if (_creation)
            const ColoredBox(
              color: Color(0x66000000),
              child: Center(child: CircularProgressIndicator.adaptive()),
            ),
        ],
      ),
    );
  }

  /// Bots correspondant à la recherche : catalogue intégré, puis ceux de
  /// l'utilisateur.
  ///
  /// Filtrés et non listés d'office : qui possède cinquante bots ne veut pas
  /// tous les dérouler avant d'atteindre ses contacts.
  List<({String mxid, String nom, String detail})> _botsTrouves(
    List<UserBot> mesBots,
  ) {
    final q = _query.toLowerCase();
    if (q.isEmpty) return const [];
    return [
      for (final bot in botCatalogue)
        (mxid: bot.matrixId, nom: bot.name, detail: bot.description),
      for (final bot in mesBots)
        (
          mxid: bot.mxid,
          nom: bot.name,
          detail: bot.description.isEmpty ? 'Votre bot' : bot.description,
        ),
    ]
        .where(
          (bot) =>
              bot.nom.toLowerCase().contains(q) ||
              bot.mxid.toLowerCase().contains(q),
        )
        .toList();
  }

  /// Coche un bot, en disant la vérité s'il ne pourra rien lire.
  ///
  /// Le groupe est chiffré et le restera : Matrix ne sait pas retirer le
  /// chiffrement. Tout se joue donc sur ce bot-ci. Un agent qui tient son
  /// propre appareil Matrix entre sans un mot ; celui qui n'a pas de clé est
  /// accepté quand même, mais prévenu, car l'invitation réussit de toute façon
  /// et un bot muet passe pour une panne de Rempart.
  Future<void> _basculerBot(({String mxid, String nom, String detail}) bot) async {
    if (_botsChoisis.containsKey(bot.mxid)) {
      setState(() => _botsChoisis.remove(bot.mxid));
      return;
    }
    if (!await ref.read(matrixServiceProvider).saitDechiffrer(bot.mxid)) {
      if (!mounted) return;
      final quandMeme = await showAdaptiveAlert<bool>(
        context: context,
        title: '${bot.nom} ne lira pas ce groupe',
        content: 'Les groupes sont chiffrés de bout en bout et ce bot ne '
            'possède pas de clé : il recevra les messages sans pouvoir les '
            'lire, et ne répondra donc pas.',
        cancelText: 'Annuler',
        confirmText: 'Ajouter quand même',
      );
      if (quandMeme != true || !mounted) return;
    }
    setState(() => _botsChoisis[bot.mxid] = bot.nom);
  }

  Widget _tuileBot(({String mxid, String nom, String detail}) bot) {
    return CheckboxListTile.adaptive(
      value: _botsChoisis.containsKey(bot.mxid),
      onChanged: (_) => _basculerBot(bot),
      secondary: const CircleAvatar(child: Icon(Icons.smart_toy_outlined)),
      title: Text(bot.nom),
      subtitle: Text(bot.detail, maxLines: 2, overflow: TextOverflow.ellipsis),
    );
  }

  Widget _buildResultats(AsyncValue<List<Profile>> resultats, ThemeData theme) {
    if (_query.isEmpty) {
      return _buildMessage(
        Icons.person_search,
        'Cherchez des participants ou un bot',
        _selection.isEmpty && _botsChoisis.isEmpty
            ? 'Un groupe demande au moins une autre personne, ou un bot'
            : '${_selection.length + _botsChoisis.length} sélectionné'
                '${_selection.length + _botsChoisis.length > 1 ? 's' : ''}',
      );
    }

    return FutureBuilder<List<UserBot>>(
      future: _mesBots,
      builder: (context, snapshot) {
        final bots = _botsTrouves(snapshot.data ?? const <UserBot>[]);

        return resultats.when(
          loading: () => const Center(child: CircularProgressIndicator.adaptive()),
          error: (e, _) => _buildMessage(
            Icons.error_outline,
            'Recherche impossible',
            '$e',
          ),
          data: (profils) {
            if (profils.isEmpty && bots.isEmpty) {
              return _buildMessage(
                Icons.search_off,
                'Aucun résultat',
                'Rien ne correspond à « $_query »',
              );
            }
            return ListView(
              children: [
                if (bots.isNotEmpty) ...[
                  _entete('Bots', theme),
                  for (final bot in bots) _tuileBot(bot),
                ],
                // Erreur affichée plutôt qu'avalée : hors Tailscale, les bots
                // de l'utilisateur disparaissaient sans un mot.
                if (snapshot.hasError)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      'Vos bots ne sont pas joignables ; seuls les bots '
                      'intégrés sont proposés.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                if (bots.isNotEmpty && profils.isNotEmpty)
                  _entete('Personnes', theme),
                for (final profile in profils)
                  CheckboxListTile.adaptive(
                    value: _selection.containsKey(profile.id),
                    onChanged: (_) => _basculer(profile),
                    secondary: UserAvatar(
                      name: profile.name,
                      imageUrl: profile.avatarUrl,
                    ),
                    title: Text(profile.name),
                    subtitle: Text('@${profile.username}'),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _entete(String titre, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(titre, style: theme.textTheme.titleSmall),
    );
  }

  Widget _buildMessage(IconData icone, String titre, String detail) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(titre, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
