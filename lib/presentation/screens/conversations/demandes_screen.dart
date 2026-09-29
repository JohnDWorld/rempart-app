import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../../../app/theme.dart';
import '../../../data/providers/providers.dart';
import '../../../data/services/matrix_service.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/common/user_avatar.dart';

/// Demandes de message : les invitations d'inconnus, en attente.
///
/// Un connu (tête-à-tête existant, ou un de ses bots) entre d'office ; tout
/// autre attend ici une décision. Tant qu'on n'a pas accepté, on n'a pas
/// rejoint le salon : l'autre ne sait pas si on a lu, et le message, chiffré,
/// n'est pas encore lisible.
class DemandesScreen extends ConsumerWidget {
  const DemandesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final demandes = ref.watch(demandesProvider);
    return AdaptiveScaffold(
      title: 'Demandes de message',
      body: demandes.isEmpty
          // L'écran reste ouvert après la dernière décision : il le dit.
          ? const Center(child: Text('Aucune demande en attente'))
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: demandes.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) =>
                  _Demande(room: demandes[index]),
            ),
    );
  }
}

class _Demande extends ConsumerStatefulWidget {
  const _Demande({required this.room});

  final matrix.Room room;

  @override
  ConsumerState<_Demande> createState() => _DemandeState();
}

class _DemandeState extends ConsumerState<_Demande> {
  bool _enCours = false;

  @override
  Widget build(BuildContext context) {
    final inviteur = MatrixService.instance.inviteurDe(widget.room) ?? '';
    final nom = ref.watch(nomContactProvider(inviteur)) ?? 'Contact inconnu';
    final groupe = widget.room.name.isEmpty ? null : widget.room.name;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RempartTokens.espaceL,
        12,
        RempartTokens.espaceL,
        12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              UserAvatar(name: nom, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nom, style: theme.textTheme.titleMedium),
                    Text(
                      groupe == null
                          ? 'souhaite vous écrire'
                          : 'vous invite dans « $groupe »',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AdaptiveButton(
                  onPressed: _enCours ? null : () => _accepter(context),
                  isLoading: _enCours,
                  child: const _Libelle('Accepter'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextButton(
                  onPressed: _enCours ? null : () => _refuser(context),
                  child: const _Libelle('Refuser'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextButton(
                  onPressed: _enCours ? null : () => _bloquer(context, nom),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  child: const _Libelle('Bloquer'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _agir(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    // Pris AVANT l'attente : une fois la demande tranchée, elle quitte la
    // liste et cette ligne est détruite. Un `ref` lu ensuite lève une erreur,
    // qui interrompait tout, jusqu'à l'ouverture de la conversation acceptée
    // (essai du 2026-09-28).
    final battement = ref.read(matrixStateNotifierProvider.notifier);
    setState(() => _enCours = true);
    try {
      await action();
    } catch (e) {
      debugPrint('Demande : action impossible ($e)');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Action impossible, vérifiez votre connexion'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _enCours = false);
      battement.state++;
    }
  }

  Future<void> _accepter(BuildContext context) async {
    final id = widget.room.id;
    // Le routeur est pris AVANT l'attente : une fois le salon rejoint, la
    // demande quitte la liste et cette ligne disparaît avec son contexte. La
    // conversation acceptée ne s'ouvrait alors jamais (essai du 2026-09-28).
    final routeur = GoRouter.of(context);
    var accepte = false;
    await _agir(context, () async {
      await MatrixService.instance.accepterDemande(widget.room);
      accepte = true;
    });
    // L'écran des demandes n'a plus lieu d'être sous la conversation.
    if (accepte) unawaited(routeur.pushReplacement('/chat/$id'));
  }

  Future<void> _refuser(BuildContext context) =>
      _agir(context, () => MatrixService.instance.refuserDemande(widget.room));

  Future<void> _bloquer(BuildContext context, String nom) async {
    final confirme = await showAdaptiveAlert<bool>(
      context: context,
      title: 'Bloquer $nom ?',
      content: 'Ses messages et ses invitations ne vous parviendront plus. '
          'Le blocage se lève depuis les paramètres.',
      cancelText: 'Annuler',
      confirmText: 'Bloquer',
      isDestructive: true,
    );
    if (confirme != true || !context.mounted) return;
    await _agir(
      context,
      () => MatrixService.instance.bloquerDemande(widget.room),
    );
  }
}

/// Libellé de bouton sur une seule ligne : un tiers de largeur ne suffisait
/// pas à « Accepter » avec les marges du bouton, qui passait à la ligne.
class _Libelle extends StatelessWidget {
  const _Libelle(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(texte, maxLines: 1, softWrap: false),
      );
}
