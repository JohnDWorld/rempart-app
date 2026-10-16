import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme.dart';
import '../../../core/utils/nom_utilisateur.dart';
import '../../../data/providers/providers.dart';
import '../../widgets/adaptive/adaptive.dart';

/// Son code QR et son lien de contact, pour qu'on vous écrive sans rien
/// taper : la personne en face scanne le code depuis « Nouveau message », ou
/// touche le lien reçu.
///
/// Le code porte le lien lui-même (`lienContact`) : scanné par l'appareil
/// photo du téléphone plutôt que par Rempart, il ouvre aussi le contact.
class MonCodeScreen extends ConsumerWidget {
  const MonCodeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profil = ref.watch(currentProfileProvider).value;
    final lien = profil == null ? null : lienContact(profil.username);

    return AdaptiveScaffold(
      title: 'Mon code QR',
      previousPageTitle: 'Paramètres',
      body: lien == null
          ? const Center(child: CircularProgressIndicator.adaptive())
          : ListView(
              padding: const EdgeInsets.all(RempartTokens.espaceL),
              children: [
                Center(
                  // Fond blanc dans les deux thèmes : un code clair sur fond
                  // sombre ne se lit pas partout.
                  child: Container(
                    padding: const EdgeInsets.all(RempartTokens.espaceL),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: QrImageView(
                      data: lien,
                      size: 240,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: RempartTokens.espaceL),
                Text(
                  profil!.name,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
                Text(
                  '@${profil.username}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
                const SizedBox(height: RempartTokens.espaceL),
                Text(
                  "Montrez ce code à quelqu'un : en le scannant depuis "
                  '« Nouveau message », il vous écrit directement, sans '
                  'risque de se tromper de personne.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: RempartTokens.espaceXl),
                AdaptiveButton(
                  onPressed: () => SharePlus.instance.share(
                    ShareParams(text: 'Écrivez-moi sur Rempart : $lien'),
                  ),
                  child: const Text('Partager mon lien'),
                ),
                const SizedBox(height: RempartTokens.espaceS),
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: lien));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Lien copié')),
                    );
                  },
                  child: const Text('Copier le lien'),
                ),
              ],
            ),
    );
  }
}
