import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Affiche la recovery key E2E à sauvegarder par l'utilisateur.
///
/// A n'afficher qu'une seule fois, après la mise en place du durcissement E2E.
/// La clé n'est pas montrée en clair par défaut : on privilégie l'export dans un
/// fichier (feuille de partage) ou l'envoi par e-mail (à garder en brouillon),
/// bien plus simples à sauvegarder durablement qu'un copier-coller.
Future<void> showRecoveryKeyDialog(
  BuildContext context,
  String recoveryKey,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _RecoveryKeyDialog(recoveryKey: recoveryKey),
  );
}

class _RecoveryKeyDialog extends StatefulWidget {
  const _RecoveryKeyDialog({required this.recoveryKey});

  final String recoveryKey;

  @override
  State<_RecoveryKeyDialog> createState() => _RecoveryKeyDialogState();
}

class _RecoveryKeyDialogState extends State<_RecoveryKeyDialog> {
  static const String _sujet = 'Clé de récupération Rempart Messenger';

  bool _revealed = false;
  bool _copied = false;

  /// Contenu du fichier / de l'e-mail : la clé accompagnée d'un rappel.
  String get _contenu => 'Clé de récupération - Rempart Messenger\n\n'
      'Conservez ceci en lieu sûr (gestionnaire de mots de passe, cloud '
      'chiffré...). Cette clé permet de récupérer vos messages chiffrés si vous '
      "oubliez votre mot de passe ou changez d'appareil. Sans elle ni votre mot "
      'de passe, ils sont définitivement perdus.\n\n'
      '${widget.recoveryKey}\n';

  Future<void> _copier() async {
    await Clipboard.setData(ClipboardData(text: widget.recoveryKey));
    if (mounted) {
      setState(() => _copied = true);
    }
  }

  /// Enregistre la clé dans un fichier choisi par l'utilisateur.
  ///
  /// Le sélecteur du système, et non le menu de partage : « Télécharger » doit
  /// poser un fichier quelque part, pas proposer de l'envoyer à une
  /// application. Le partage restait d'ailleurs le pire chemin pour un secret,
  /// puisqu'il invite à le confier à un tiers.
  ///
  /// Les octets sont passés au sélecteur, qui écrit lui-même : sur Android
  /// l'application n'a pas le droit d'écrire dans « Téléchargements », seul le
  /// système l'a.
  Future<void> _telecharger() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final chemin = await FilePicker.platform.saveFile(
        dialogTitle: 'Enregistrer la clé de récupération',
        fileName: 'cle-recuperation-rempart.txt',
        bytes: Uint8List.fromList(utf8.encode(_contenu)),
        type: FileType.custom,
        allowedExtensions: ['txt'],
      );
      if (!mounted) return;
      // null : l'utilisateur a refermé le sélecteur. Rien à signaler, il n'a
      // rien demandé de plus.
      if (chemin == null) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Clé de récupération enregistrée')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text("Échec de l'enregistrement : $e")),
      );
    }
  }

  Future<void> _envoyerParMail() async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.parse(
      'mailto:?subject=${Uri.encodeComponent(_sujet)}'
      '&body=${Uri.encodeComponent(_contenu)}',
    );
    try {
      final ouvert = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ouvert) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Aucune application e-mail trouvée.')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text("Impossible d'ouvrir la messagerie : $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      icon: const Icon(Icons.key, color: Colors.green),
      title: const Text('Ta clé de récupération'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sauvegarde cette clé en lieu sûr. Elle permet de récupérer tes '
              'messages chiffrés si tu oublies ton mot de passe ou changes '
              "d'appareil. Sans elle ni ton mot de passe, ils seront perdus.",
            ),
            const SizedBox(height: 16),
            // Actions recommandées : bien plus fiables qu'un copier-coller.
            FilledButton.icon(
              onPressed: _telecharger,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Télécharger le fichier'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _envoyerParMail,
              icon: const Icon(Icons.mail_outline),
              label: const Text('Envoyer par e-mail'),
            ),
            const SizedBox(height: 16),
            // Repli : afficher la clé pour la recopier à la main si besoin.
            InkWell(
              onTap: () => setState(() => _revealed = !_revealed),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _revealed
                          ? SelectableText(
                              widget.recoveryKey,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontFamily: 'monospace',
                                letterSpacing: 1,
                              ),
                            )
                          : Text(
                              'Appuyer pour afficher la clé',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                    ),
                    Icon(
                      _revealed ? Icons.visibility_off : Icons.visibility,
                      size: 20,
                      color: theme.colorScheme.outline,
                    ),
                  ],
                ),
              ),
            ),
            if (_revealed)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _copier,
                  icon: Icon(_copied ? Icons.check : Icons.copy, size: 18),
                  label: Text(_copied ? 'Copiée' : 'Copier'),
                ),
              ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("J'ai sauvegardé ma clé"),
        ),
      ],
    );
  }
}
