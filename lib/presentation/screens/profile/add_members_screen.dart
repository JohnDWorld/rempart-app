import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/bot.dart';
import '../../../data/models/profile.dart';
import '../../../data/models/user_bot.dart';
import '../../../data/providers/providers.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/common/user_avatar.dart';

/// Ajout de membres à un groupe existant.
///
/// Une personne touchée est invitée aussitôt : pas de sélection multiple à
/// valider, on reste sur l'écran pour en ajouter d'autres et chaque invitation
/// affiche son sort. Les membres déjà présents restent visibles, grisés, plutôt
/// que masqués : sans cela, chercher quelqu'un qui est déjà là ne donne aucun
/// résultat et laisse croire à une erreur.
class AddMembersScreen extends ConsumerStatefulWidget {
  const AddMembersScreen({required this.roomId, super.key});

  final String roomId;

  @override
  ConsumerState<AddMembersScreen> createState() => _AddMembersScreenState();
}

class _AddMembersScreenState extends ConsumerState<AddMembersScreen> {
  final _rechercheController = TextEditingController();

  /// mxid invités depuis cet écran, pour l'afficher sans attendre le sync.
  final _invites = <String>{};

  Timer? _debounce;
  String _query = '';
  bool _envoi = false;

  /// Bots de l'utilisateur, chargés une fois. La liste est courte (quota par
  /// défaut : 10), inutile de la filtrer côté serveur.
  Future<List<UserBot>>? _mesBots;

  @override
  void initState() {
    super.initState();
    _mesBots = ref.read(botGatewayServiceProvider).myBots().then((l) => l.bots);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _rechercheController.dispose();
    super.dispose();
  }

  void _onRechercheChanged(String value) {
    // Anti-rebond : chaque frappe interrogerait Supabase.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  Future<void> _inviter(Profile profile) {
    // Le mxid dérive de l'id Supabase (schéma unifié `u_<uuid>`), jamais du
    // username du profil : `@username` n'existe pas côté Matrix.
    return _inviterMxid(
      ref.read(matrixServiceProvider).matrixUserIdForSupabaseId(profile.id),
    );
  }

  /// Invite un bot, après s'être assuré qu'il pourra lire quelque chose.
  ///
  /// Le groupe est chiffré et le reste : Matrix ne sait pas retirer le
  /// chiffrement d'un salon. La seule question est donc de savoir si ce
  /// bot-là tient des clés. Un agent qui a son propre appareil Matrix entre
  /// sans qu'on demande rien ; un bot de la passerelle, qui n'en a pas,
  /// n'est pas interdit pour autant, mais on dit ce qui l'attend. Le refuser
  /// serait pire : l'invitation réussit toujours côté serveur, et un bot
  /// silencieux se lit comme une panne de Rempart.
  Future<void> _inviterBot(String mxid, String nom, {required bool chiffre}) async {
    if (chiffre && !await ref.read(matrixServiceProvider).saitDechiffrer(mxid)) {
      if (!mounted) return;
      final quandMeme = await showAdaptiveAlert<bool>(
        context: context,
        title: '$nom ne lira pas ce groupe',
        content: 'Ce groupe est chiffré de bout en bout et ce bot ne possède '
            'pas de clé : il recevra les messages sans pouvoir les lire, et '
            'ne répondra donc pas.\n\nLe chiffrement ne peut pas être retiré '
            "d'un groupe existant.",
        cancelText: 'Annuler',
        confirmText: 'Ajouter quand même',
      );
      if (quandMeme != true) return;
    }
    await _inviterMxid(mxid);
  }

  Future<void> _inviterMxid(String mxid) async {
    if (_envoi) return;
    setState(() => _envoi = true);
    final matrixService = ref.read(matrixServiceProvider);
    try {
      await matrixService.inviteToRoom(widget.roomId, mxid);
      ref.read(matrixStateNotifierProvider.notifier).state++;
      ref.invalidate(roomMembersProvider(widget.roomId));
      if (mounted) setState(() => _invites.add(mxid));
    } catch (e) {
      if (mounted) {
        await showAdaptiveAlert<void>(
          context: context,
          title: 'Invitation impossible',
          content: '$e',
        );
      }
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final resultats = _query.isEmpty
        ? const AsyncValue<List<Profile>>.data(<Profile>[])
        : ref.watch(profileSearchProvider(_query));
    final membres =
        ref.watch(roomMembersProvider(widget.roomId)).value ?? const [];
    final dejaLa = membres.map((m) => m.id).toSet()..addAll(_invites);
    final matrixService = ref.watch(matrixServiceProvider);
    final chiffre = ref.watch(roomProvider(widget.roomId))?.encrypted ?? false;

    return AdaptiveScaffold(
      title: 'Ajouter des membres',
      previousPageTitle: 'Retour',
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: AdaptiveTextField(
              controller: _rechercheController,
              placeholder: 'Rechercher un contact ou un bot',
              autofocus: true,
              onChanged: _onRechercheChanged,
            ),
          ),
          ..._sectionBots(chiffre: chiffre, dejaLa: dejaLa),
          _entete('Personnes'),
          ...resultats.when(
            loading: () => [
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator.adaptive()),
              ),
            ],
            error: (e, _) => [_message('Recherche impossible', '$e')],
            data: (profils) {
              if (_query.isEmpty) {
                return [
                  _message(
                    'Cherchez une personne',
                    "Touchez un résultat pour l'inviter dans le groupe",
                  ),
                ];
              }
              if (profils.isEmpty) {
                return [
                  _message(
                    'Aucun contact',
                    'Personne ne correspond à « $_query »',
                  ),
                ];
              }
              return profils.map((profile) {
                final mxid =
                    matrixService.matrixUserIdForSupabaseId(profile.id);
                final present = dejaLa.contains(mxid);
                return AdaptiveListTile(
                  leading: UserAvatar(
                    name: profile.name,
                    imageUrl: profile.avatarUrl,
                    size: 40,
                  ),
                  title: Text(profile.name),
                  subtitle: Text(
                    present ? 'Déjà dans le groupe' : '@${profile.username}',
                  ),
                  trailing: present ? const Icon(Icons.check) : null,
                  onTap: present ? null : () => _inviter(profile),
                );
              }).toList();
            },
          ),
        ],
      ),
    );
  }

  /// Section « Bots », proposée même dans un groupe chiffré.
  ///
  /// Tous les bots ne sont pas aveugles au chiffrement : celui qui tient son
  /// propre appareil Matrix lit le salon comme un membre ordinaire. C'est au
  /// moment de l'ajout qu'on tranche, bot par bot, plutôt qu'en masquant la
  /// section entière.
  List<Widget> _sectionBots({
    required bool chiffre,
    required Set<String> dejaLa,
  }) {
    // Rien tant qu'on ne cherche pas : dérouler d'office les bots de quelqu'un
    // qui en possède cinquante enterrerait ses contacts.
    if (_query.isEmpty) return const [];

    return [
      _entete('Bots'),
      FutureBuilder<List<UserBot>>(
        future: _mesBots,
        builder: (context, snapshot) {
          // Erreur affichée, et non avalée : sans cela, une gateway
          // injoignable (Tailscale coupé, réseau mobile) faisait simplement
          // disparaître les bots de l'utilisateur de la liste, ce qui se lit
          // comme « impossible d'ajouter mon bot » au lieu de « serveur
          // injoignable ».

          final proposes = <({String mxid, String nom, String detail})>[
            for (final bot in botCatalogue)
              (mxid: bot.matrixId, nom: bot.name, detail: bot.description),
            for (final bot in snapshot.data ?? const <UserBot>[])
              (
                mxid: bot.mxid,
                nom: bot.name,
                detail: bot.description.isEmpty ? 'Votre bot' : bot.description,
              ),
          ].where((bot) {
            final q = _query.toLowerCase();
            return bot.nom.toLowerCase().contains(q) ||
                bot.mxid.toLowerCase().contains(q);
          }).toList();

          if (proposes.isEmpty && !snapshot.hasError) {
            return _message('Aucun bot', 'Rien ne correspond à « $_query »');
          }
          return Column(
            children: [
              // Erreur affichée plutôt qu'avalée : sans cela, une gateway
              // injoignable (Tailscale coupé, réseau mobile) faisait
              // simplement disparaître les bots de l'utilisateur, ce qui se
              // lit comme « impossible d'ajouter mon bot » au lieu de
              // « serveur injoignable ». Le catalogue, lui, reste proposé.
              if (snapshot.hasError)
                _message(
                  'Vos bots ne sont pas joignables',
                  'Le serveur des bots ne répond pas ; seuls les bots intégrés '
                      'sont proposés.\n${snapshot.error}',
                ),
              for (final bot in proposes)
                AdaptiveListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.smart_toy_outlined),
                  ),
                  title: Text(bot.nom),
                  subtitle: Text(
                    dejaLa.contains(bot.mxid)
                        ? 'Déjà dans le groupe'
                        : bot.detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: dejaLa.contains(bot.mxid)
                      ? const Icon(Icons.check)
                      : null,
                  onTap: dejaLa.contains(bot.mxid)
                      ? null
                      : () => _inviterBot(
                            bot.mxid,
                            bot.nom,
                            chiffre: chiffre,
                          ),
                ),
            ],
          );
        },
      ),
    ];
  }

  Widget _entete(String titre) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(titre, style: Theme.of(context).textTheme.titleSmall),
    );
  }

  Widget _message(String titre, String detail) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(titre, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(detail, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
