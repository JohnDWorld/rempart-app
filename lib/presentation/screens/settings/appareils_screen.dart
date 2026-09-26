import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../../../app/theme.dart';
import '../../../core/plateforme.dart';
import '../../../data/providers/providers.dart';
import '../../../data/services/appairage_service.dart';
import '../../../services/auth_service.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/settings/scanner_qr.dart';
import '../../widgets/settings/verification_appareil.dart';

/// Sessions Matrix ouvertes sur le compte, et de quoi les fermer.
///
/// Chaque appareil connecté détient ses propres clés de déchiffrement : c'est
/// l'écran qu'on ouvre après avoir perdu un téléphone. Fermer une session la
/// coupe du serveur, mais ne réécrit pas l'historique déjà déchiffré chez elle.
class AppareilsScreen extends ConsumerStatefulWidget {
  const AppareilsScreen({super.key});

  @override
  ConsumerState<AppareilsScreen> createState() => _AppareilsScreenState();
}

class _AppareilsScreenState extends ConsumerState<AppareilsScreen> {
  late Future<List<matrix.Device>> _appareils;

  /// Session en cours de fermeture, pour n'en griser qu'une.
  String? _fermeture;

  @override
  void initState() {
    super.initState();
    _appareils = ref.read(matrixServiceProvider).appareils();
  }

  void _recharger() {
    setState(() {
      _appareils = ref.read(matrixServiceProvider).appareils();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final courant = ref.read(matrixServiceProvider).appareilCourant;

    return AdaptiveScaffold(
      title: 'Appareils connectés',
      previousPageTitle: 'Paramètres',
      actions: [
        // Réservé au mobile : approuver suppose de scanner, donc une caméra.
        if (!estWeb)
          IconButton(
            icon: const Icon(Icons.add_to_home_screen),
            tooltip: 'Connecter un appareil',
            onPressed: _connecterUnAppareil,
          ),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Actualiser',
          onPressed: _recharger,
        ),
      ],
      body: FutureBuilder<List<matrix.Device>>(
        future: _appareils,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          if (snapshot.hasError) {
            return _Message(
              icone: Icons.cloud_off,
              titre: 'Liste indisponible',
              detail: '${snapshot.error}',
              action: _recharger,
            );
          }

          final appareils = snapshot.data ?? [];
          if (appareils.isEmpty) {
            return const _Message(
              icone: Icons.devices_other,
              titre: 'Aucun appareil',
              detail: 'Le serveur ne signale aucune session ouverte.',
            );
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: RempartTokens.espaceXl),
            children: [
              Padding(
                padding: const EdgeInsets.all(RempartTokens.espaceL),
                child: Text(
                  'Chaque appareil connecté peut lire vos conversations. '
                  'Fermez ceux que vous ne reconnaissez pas ou que vous '
                  "n'utilisez plus.",
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              for (final appareil in appareils)
                _Appareil(
                  appareil: appareil,
                  estCeluiCi: appareil.deviceId == courant,
                  enCours: _fermeture == appareil.deviceId,
                  confiance: etatConfiance(
                    ref.read(matrixServiceProvider).clesAppareil(
                          appareil.deviceId,
                        ),
                  ),
                  onFermer: () => _fermer(appareil),
                  onVerifier: () => _verifier(appareil),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Ouvre une session sur un autre appareil, en scannant le code qu'il
  /// affiche.
  ///
  /// La confirmation est demandée **après** le scan et avant tout appel : ce
  /// geste ouvre une session sur le compte, il ne doit jamais partir d'un
  /// cadrage involontaire de la caméra.
  Future<void> _connecterUnAppareil() async {
    final contenu = await scannerTexteQr(
      context,
      titre: 'Connecter un appareil',
      consigne: "Visez le code affiché par l'appareil à connecter.",
      accepter: AppairageService.ressembleAUnCodeRempart,
    );
    if (contenu == null || !mounted) return;

    final accepte = await showAdaptiveAlert<bool>(
      context: context,
      title: 'Ouvrir une session ?',
      content: "Cet appareil pourra lire vos conversations, jusqu'à ce que "
          'vous fermiez sa session depuis cet écran.',
      cancelText: 'Annuler',
      confirmText: 'Ouvrir la session',
      isDestructive: true,
    );
    if (accepte != true || !mounted) return;

    try {
      await AppairageService().approuver(contenu);
      if (mounted) _signaler("Session ouverte sur l'autre appareil.");
    } catch (e) {
      if (mounted) _signaler('Connexion refusée : $e', erreur: true);
    }
    if (mounted) _recharger();
  }

  /// Lance la comparaison d'emojis avec un autre de nos appareils.
  ///
  /// C'est le seul geste qui établit qu'un appareil est bien le nôtre. Le
  /// chiffrement, lui, garantit seulement que personne d'autre que « les
  /// appareils du compte » ne lit, sans jamais dire qui ils sont.
  Future<void> _verifier(matrix.Device appareil) async {
    final verification = await ref
        .read(matrixServiceProvider)
        .verifierAppareil(appareil.deviceId);
    if (!mounted) return;
    if (verification == null) {
      _signaler(
        'Clés de cet appareil pas encore connues, réessayez dans un instant.',
        erreur: true,
      );
      return;
    }
    await ouvrirVerification(verification, nousAvonsDemande: true);
    // L'état de confiance a pu changer : la liste doit le refléter.
    if (mounted) _recharger();
  }

  Future<void> _fermer(matrix.Device appareil) async {
    final nom = appareil.displayName ?? appareil.deviceId;
    final confirme = await showAdaptiveAlert<bool>(
      context: context,
      title: 'Fermer la session',
      content: '« $nom » sera déconnecté et devra se reconnecter pour '
          'accéder au compte.',
      cancelText: 'Annuler',
      confirmText: 'Fermer',
      isDestructive: true,
    );
    if (confirme != true || !mounted) return;

    setState(() => _fermeture = appareil.deviceId);
    try {
      // Le mot de passe Matrix est aléatoire et gardé dans le secure storage :
      // il répond à la ré-authentification exigée par le serveur sans que
      // l'utilisateur ait à taper quoi que ce soit.
      final motDePasse = await ref.read(authServiceProvider).motDePasseMatrix();
      if (motDePasse == null) throw Exception('session Matrix introuvable');
      await ref
          .read(matrixServiceProvider)
          .fermerAppareil(appareil.deviceId, motDePasse);
      if (!mounted) return;
      _signaler('Session fermée');
      _recharger();
    } catch (e) {
      _signaler('Fermeture impossible : $e', erreur: true);
    } finally {
      if (mounted) setState(() => _fermeture = null);
    }
  }

  void _signaler(String message, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: erreur ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }
}

class _Appareil extends StatelessWidget {
  const _Appareil({
    required this.appareil,
    required this.estCeluiCi,
    required this.enCours,
    required this.confiance,
    required this.onFermer,
    required this.onVerifier,
  });

  final matrix.Device appareil;
  final bool estCeluiCi;
  final bool enCours;

  /// Null tant que les clés ne sont pas chargées : on n'affiche alors rien
  /// plutôt que « non vérifié », qui serait faux.
  final ({String texte, bool sur})? confiance;
  final VoidCallback onFermer;
  final VoidCallback onVerifier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nom = appareil.displayName ?? 'Appareil sans nom';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: estCeluiCi
            ? theme.colorScheme.primary.withValues(alpha: 0.12)
            : theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          estCeluiCi ? Icons.smartphone : Icons.devices_other,
          color: estCeluiCi
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      title: Row(
        children: [
          Flexible(child: Text(nom, overflow: TextOverflow.ellipsis)),
          if (estCeluiCi) ...[
            const SizedBox(width: RempartTokens.espaceS),
            const _Pastille(texte: 'Cet appareil'),
          ],
          if (confiance != null) ...[
            const SizedBox(width: RempartTokens.espaceS),
            _Pastille(texte: confiance!.texte, sur: confiance!.sur),
          ],
        ],
      ),
      subtitle: Text(
        _details(),
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      isThreeLine: true,
      trailing: estCeluiCi
          // Fermer la session courante, c'est se déconnecter : cela se fait
          // depuis le profil, avec la confirmation qui va avec.
          ? null
          : enCours
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Proposé seulement là où il y a quelque chose à faire :
                    // un appareil déjà vérifié n'a pas à l'être deux fois, et
                    // tant que ses clés sont inconnues la demande échouerait.
                    if (confiance != null && !confiance!.sur)
                      IconButton(
                        icon: const Icon(Icons.verified_user_outlined),
                        tooltip: 'Vérifier cet appareil',
                        onPressed: onVerifier,
                      ),
                    IconButton(
                      icon: Icon(Icons.logout, color: theme.colorScheme.error),
                      tooltip: 'Fermer la session',
                      onPressed: onFermer,
                    ),
                  ],
                ),
    );
  }

  /// Identifiant, dernière activité et adresse : de quoi reconnaître un
  /// appareil dont le nom ne dit rien.
  String _details() {
    final lignes = <String>[appareil.deviceId];
    final vuLe = appareil.lastSeenTs;
    if (vuLe != null) {
      final date = DateTime.fromMillisecondsSinceEpoch(vuLe);
      lignes.add('Vu le ${DateFormat('d MMM y à HH:mm', 'fr_FR').format(date)}');
    }
    final ip = appareil.lastSeenIp;
    if (ip != null && ip.isNotEmpty) lignes.add(ip);
    return lignes.join(' · ');
  }
}

class _Pastille extends StatelessWidget {
  const _Pastille({required this.texte, this.sur});

  final String texte;

  /// Trois valeurs et non deux : `null` pour une pastille neutre (« Cet
  /// appareil »), qui ne dit rien de la confiance.
  final bool? sur;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final couleur = switch (sur) {
      true => RempartTokens.texteSucces(theme.brightness),
      false => theme.colorScheme.error,
      null => theme.colorScheme.primary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        texte,
        style: theme.textTheme.labelSmall?.copyWith(color: couleur),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icone,
    required this.titre,
    required this.detail,
    this.action,
  });

  final IconData icone;
  final String titre;
  final String detail;
  final VoidCallback? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RempartTokens.espaceXl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icone, size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: RempartTokens.espaceL),
            Text(titre, style: theme.textTheme.titleMedium),
            const SizedBox(height: RempartTokens.espaceS),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (action != null) ...[
              const SizedBox(height: RempartTokens.espaceL),
              AdaptiveTextButton(onPressed: action, child: const Text('Réessayer')),
            ],
          ],
        ),
      ),
    );
  }
}
