import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../data/services/update_service.dart';

/// Version installée, sous la forme « 1.0.0 (build 3) ».
///
/// Lue à l'exécution : écrite en dur, elle mentirait dès la première mise à
/// jour, c'est-à-dire précisément au moment où on la consulte.
Future<String> versionInstallee() async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version} (build ${info.buildNumber})';
}

/// Propose une mise à jour trouvée, puis la télécharge et l'installe.
///
/// Rien ne se fait sans accord : cette boîte d'abord, l'écran de confirmation
/// d'Android ensuite. L'application ne peut pas se remplacer en silence, et
/// c'est très bien ainsi.
///
/// Renvoie vrai si l'utilisateur a **décliné**, seul cas où l'appelant doit
/// refermer la fenêtre de vérification. Passé le « Installer », on ne sait
/// pas ce qu'il advient : l'installateur d'Android peut être annulé, refusé
/// par Play Protect, ou aboutir. Dans les deux premiers cas la mise à jour
/// reste à faire et doit être reproposée ; dans le troisième l'application
/// est remplacee et la question ne se pose plus.
Future<bool> proposerMiseAJour(
  BuildContext context,
  VersionDisponible version,
) async {
  final accepte = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.system_update),
      title: const Text('Mise à jour disponible'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Version ${version.versionName} (build ${version.versionCode})',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          if (version.notes.isNotEmpty) ...[
            Text(version.notes),
            const SizedBox(height: 12),
          ],
          Text(
            '${(version.taille / 1024 / 1024).toStringAsFixed(1)} Mo à '
            'télécharger.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Plus tard'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          // « Télécharger » et non « Installer » : c'est ce que fait ce
          // bouton. L'installation vient après, quand les 104 Mo sont là.
          child: const Text('Télécharger'),
        ),
      ],
    ),
  );
  if (accepte != true) return true;
  if (!context.mounted) return false;

  // Android 8 et suivants accordent le droit d'installer application par
  // application. Sans ce détour, l'écran d'installation s'ouvre sur un refus
  // que rien n'explique.
  if (!await UpdateService.instance.peutInstaller()) {
    if (!context.mounted) return false;
    final vaAuxReglages = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.shield_outlined),
        title: const Text('Autorisation nécessaire'),
        content: const Text(
          "Android demande votre accord pour qu'une application puisse en "
          'installer une autre. Autorisez Rempart, puis relancez la mise à '
          'jour.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ouvrir les réglages'),
          ),
        ],
      ),
    );
    if (vaAuxReglages ?? false) {
      await UpdateService.instance.ouvrirReglageInstallation();
    }
    // L'autorisation manquait : la mise à jour reste entière à faire.
    return false;
  }

  if (!context.mounted) return false;

  // Plus de fenêtre bloquante pendant le téléchargement : c'était le piège.
  // L'utilisatrice devait garder Rempart au premier plan, écran allumé, le
  // temps de 87 Mo ; verrouiller son téléphone faisait tout recommencer. Le
  // système télécharge maintenant de son côté, et prévient quand c'est prêt.
  final messenger = ScaffoldMessenger.of(context);
  try {
    final lance = await UpdateService.instance.telechargerEnFond(version);
    if (!lance) {
      // Rien à télécharger, l'APK est déjà là : autant ouvrir l'installateur
      // tout de suite. Renvoyer l'utilisateur vers une notification pour un
      // fichier qu'il a déjà, c'est ce qui rendait la mise à jour impossible
      // quand la notification avait été balayée.
      final chemin = await UpdateService.instance.cheminApkPret(version);
      if (chemin != null) {
        await UpdateService.instance.installer(chemin);
        return false;
      }
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          lance
              ? 'Téléchargement lancé. Vous pouvez fermer Rempart : une '
                  'notification vous préviendra quand la mise à jour sera '
                  'prête à installer, et le bouton passera à « Installer ».'
              : 'Mise à jour déjà téléchargée : ouvrez « Installer la mise à '
                  'jour » dans les paramètres.',
        ),
        duration: const Duration(seconds: 6),
      ),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Téléchargement impossible : $e')),
    );
  }
  return false;
}

/// Entrée « Rechercher une mise à jour » des paramètres.
///
/// Ne s'affiche pas si la fonctionnalité n'est pas active dans ce build (URL
/// absente du `.env`) ni sur iOS, où Apple interdit toute installation hors de
/// l'App Store.
class MiseAJourTile extends StatefulWidget {
  const MiseAJourTile({super.key});

  @override
  State<MiseAJourTile> createState() => _MiseAJourTileState();
}

class _MiseAJourTileState extends State<MiseAJourTile> {
  bool _enCours = false;

  /// Version publiée plus récente que la nôtre, si le serveur en annonce une.
  VersionDisponible? _version;

  /// Chemin de son APK s'il est déjà là, vérifié : le bouton dit alors
  /// « Installer » au lieu de « Télécharger ».
  String? _apkPret;

  /// Téléchargement en cours, avec son avancement.
  ///
  /// Sans cet état, l'écran affichait « Télécharger » pendant que le système
  /// travaillait : rien ne disait que c'était parti, et un second appui
  /// relançait 104 Mo par-dessus le premier.
  ProgressionMaj? _progression;

  /// Surveille la fin d'un téléchargement pendant que l'écran est ouvert.
  ///
  /// `DownloadManager` travaille de son côté et ne prévient que par une
  /// notification. Sans cette veille, l'utilisateur resté sur cet écran
  /// verrait « Télécharger » alors que l'APK vient d'arriver.
  Timer? _veille;

  @override
  void initState() {
    super.initState();
    unawaited(_etatInitial());
  }

  @override
  void dispose() {
    _veille?.cancel();
    super.dispose();
  }

  /// Interroge le serveur en silence à l'ouverture de l'écran.
  ///
  /// Sans erreur affichée : hors du réseau, l'entrée reste simplement sur
  /// « Rechercher une mise à jour », que l'utilisateur peut toucher.
  Future<void> _etatInitial() async {
    final version = await UpdateService.instance.chercherMiseAJour();
    if (version == null || !mounted) return;
    final chemin = await UpdateService.instance.cheminApkPret(version);
    final progression = await UpdateService.instance.progression();
    if (!mounted) return;
    setState(() {
      _version = version;
      _apkPret = chemin;
      _progression = progression;
    });
    // Un téléchargement lancé avant, qui tourne toujours : on reprend sa
    // surveillance, sinon le bouton resterait figé sur « Téléchargement... »
    // jusqu'à ce qu'on ressorte de l'écran.
    if (chemin == null && progression != null) _surveillerTelechargement();
  }

  @override
  Widget build(BuildContext context) {
    if (!UpdateService.instance.disponible) return const SizedBox.shrink();

    final version = _version;
    final pret = _apkPret != null;
    final enTelechargement = !pret && _progression != null;

    final titre = version == null
        ? 'Rechercher une mise à jour'
        : pret
            ? 'Installer la mise à jour'
            : enTelechargement
                ? 'Téléchargement...'
                : 'Télécharger la mise à jour';

    return ListTile(
      leading: Icon(
        pret
            ? Icons.install_mobile
            : enTelechargement
                ? Icons.downloading
                : Icons.system_update,
      ),
      title: Text(titre),
      // Le sous-titre porte alors deux lignes (le texte et la barre) : sans
      // cela `ListTile` garde la hauteur d'une seule et la barre déborde.
      isThreeLine: enTelechargement,
      subtitle: version == null ? null : _detail(version, pret: pret),
      trailing: _enCours
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : enTelechargement
              // Rien à droite pendant le téléchargement : la barre du dessous
              // porte déjà l'information, et un chevron inviterait à toucher
              // une entrée devenue muette.
              ? null
              : const Icon(Icons.chevron_right),
      // Muet pendant le téléchargement : c'est ce qui empêche d'en lancer un
      // second par-dessus le premier.
      onTap: _enCours || enTelechargement ? null : _agir,
    );
  }

  /// Ligne du dessous : ce qu'on attend, et où l'on en est.
  Widget _detail(VersionDisponible version, {required bool pret}) {
    final entete =
        'Version ${version.versionName} (build ${version.versionCode})';
    final progression = _progression;

    if (pret) return Text('$entete · prête');

    if (progression != null) {
      final fait = (progression.octets / 1024 / 1024).toStringAsFixed(0);
      final total = (version.taille / 1024 / 1024).toStringAsFixed(0);
      // « En pause » plutôt que « en cours » quand le système a suspendu :
      // l'utilisateur voit un chiffre qui n'avance plus, autant lui dire
      // pourquoi. Il n'a rien à faire, la reprise est automatique.
      final etat = progression.enPause ? ' · en pause' : '';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$entete · $fait Mo sur $total$etat'),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              // Se remplit quand la taille est connue, et ondule sans fin
              // sinon : un pourcentage faux vaut moins que pas de pourcentage.
              value: progression.fraction,
              minHeight: 5,
            ),
          ),
        ],
      );
    }

    return Text(
      '$entete · ${(version.taille / 1024 / 1024).toStringAsFixed(0)} Mo',
    );
  }

  Future<void> _agir() async {
    final version = _version;
    if (version == null) return _verifier();
    final chemin = _apkPret;
    if (chemin != null) {
      // Android ouvre son propre écran de confirmation : rien ne s'installe
      // sans un geste de plus.
      try {
        await UpdateService.instance.installer(chemin);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Installation impossible : $e')),
        );
      }
      return;
    }
    await proposerMiseAJour(context, version);
    // Relevé immédiat : attendre le premier battement laisserait le bouton sur
    // « Télécharger », et cliquable, pendant la seconde qui suit le lancement.
    final progression = await UpdateService.instance.progression();
    if (mounted) setState(() => _progression = progression);
    _surveillerTelechargement();
  }

  /// Suit le téléchargement : avancement, puis bascule en « Installer ».
  ///
  /// Une seconde entre deux relevés : c'est le rythme auquel un chiffre qui
  /// avance se lit comme vivant, sans interroger le système pour rien.
  void _surveillerTelechargement() {
    _veille?.cancel();
    _veille = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final version = _version;
      if (!mounted || version == null) {
        timer.cancel();
        return;
      }
      final chemin = await UpdateService.instance.cheminApkPret(version);
      if (chemin != null) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _apkPret = chemin;
            _progression = null;
          });
        }
        return;
      }
      final progression = await UpdateService.instance.progression();
      if (!mounted) return;
      // Plus de téléchargement et pas d'APK prêt : il a échoué ou été annulé.
      // On rend la main plutôt que de laisser « Téléchargement... » éternel.
      if (progression == null) timer.cancel();
      setState(() => _progression = progression);
    });
  }

  Future<void> _verifier() async {
    setState(() => _enCours = true);
    final version = await UpdateService.instance.chercherMiseAJour();
    if (!mounted) return;
    final chemin = version == null
        ? null
        : await UpdateService.instance.cheminApkPret(version);
    final progression =
        chemin == null ? await UpdateService.instance.progression() : null;
    if (!mounted) return;
    setState(() {
      _enCours = false;
      _version = version;
      _apkPret = chemin;
      _progression = progression;
    });
    // Un téléchargement déjà en route : le suivre plutôt que d'en proposer un
    // second, ce que faisait la recherche manuelle.
    if (progression != null) {
      _surveillerTelechargement();
      return;
    }
    if (version == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vous avez déjà la dernière version.')),
      );
      return;
    }
    if (chemin == null) {
      await proposerMiseAJour(context, version);
      final lance = await UpdateService.instance.progression();
      if (mounted) setState(() => _progression = lance);
      _surveillerTelechargement();
    }
  }
}
