import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme.dart';
import '../../../data/providers/providers.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/common/user_avatar.dart';

/// Édition de son propre profil : photo, nom affiché, bio.
///
/// Les trois vivent dans Supabase, source de vérité des identités. Le nom est
/// en plus recopié dans le profil Matrix : c'est celui que lisent les bots
/// pour savoir qui a écrit quoi dans un groupe.
class ModifierProfilScreen extends ConsumerStatefulWidget {
  const ModifierProfilScreen({super.key});

  @override
  ConsumerState<ModifierProfilScreen> createState() =>
      _ModifierProfilScreenState();
}

class _ModifierProfilScreenState extends ConsumerState<ModifierProfilScreen> {
  final _nomController = TextEditingController();
  final _bioController = TextEditingController();

  /// Vrai tant que les champs n'ont pas reçu les valeurs du profil chargé.
  /// Sans ce drapeau, chaque reconstruction écraserait la saisie en cours.
  bool _champsRemplis = false;

  bool _enregistrement = false;
  bool _photoEnCours = false;

  @override
  void dispose() {
    _nomController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profil = ref.watch(currentProfileProvider).value;

    if (profil != null && !_champsRemplis) {
      _nomController.text = profil.displayName ?? profil.username;
      _bioController.text = profil.bio ?? '';
      _champsRemplis = true;
    }

    return AdaptiveScaffold(
      title: 'Modifier le profil',
      previousPageTitle: 'Profil',
      body: ListView(
        padding: const EdgeInsets.all(RempartTokens.espaceL),
        children: [
          Center(
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                UserAvatar(
                  name: profil?.name ?? '',
                  imageUrl: profil?.avatarUrl,
                  size: 108,
                  onTap: _photoEnCours ? null : _changerPhoto,
                ),
                // Pastille d'appareil photo : sans elle, rien ne dit que
                // l'avatar est un bouton.
                Material(
                  color: theme.colorScheme.primary,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _photoEnCours ? null : _changerPhoto,
                    child: Padding(
                      padding: const EdgeInsets.all(RempartTokens.espaceS),
                      child: _photoEnCours
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.onPrimary,
                              ),
                            )
                          : Icon(
                              Icons.photo_camera,
                              size: 18,
                              color: theme.colorScheme.onPrimary,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: RempartTokens.espaceXl),
          AdaptiveTextField(
            controller: _nomController,
            label: 'Nom affiché',
            placeholder: 'Le nom que voient vos contacts',
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: RempartTokens.espaceL),
          AdaptiveTextField(
            controller: _bioController,
            label: 'Bio',
            placeholder: 'Quelques mots sur vous (facultatif)',
            maxLines: 3,
          ),
          const SizedBox(height: RempartTokens.espaceL),
          Text(
            'Votre identifiant et votre adresse e-mail ne changent pas : '
            'ils identifient votre compte.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: RempartTokens.espaceXl),
          AdaptiveButton(
            onPressed: (_enregistrement || profil == null) ? null : _enregistrer,
            isLoading: _enregistrement,
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  Future<void> _changerPhoto() async {
    final aUnePhoto =
        ref.read(currentProfileProvider).value?.avatarUrl?.isNotEmpty ?? false;
    final source = await showAdaptiveActionSheet<String>(
      context: context,
      title: 'Photo de profil',
      actions: [
        const AdaptiveAction(label: 'Depuis la galerie', value: 'galerie'),
        const AdaptiveAction(label: 'Appareil photo', value: 'camera'),
        if (aUnePhoto)
          const AdaptiveAction(
            label: 'Retirer la photo',
            value: 'retirer',
            isDestructive: true,
          ),
      ],
      cancelAction: const AdaptiveAction(label: 'Annuler'),
    );
    if (source == null || !mounted) return;

    File? fichier;
    if (source != 'retirer') {
      final choisi = await ImagePicker().pickImage(
        source:
            source == 'camera' ? ImageSource.camera : ImageSource.gallery,
        // Le bucket refuse au-delà de 5 Mo et un avatar ne s'affiche jamais
        // plus grand que quelques centaines de pixels : redimensionner à la
        // prise évite un envoi inutilement lourd, et le refus qui va avec.
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (choisi == null) return;
      fichier = File(choisi.path);
    }

    setState(() => _photoEnCours = true);
    try {
      final service = ref.read(profileServiceProvider);
      if (fichier == null) {
        await service.deleteAvatar();
      } else {
        await service.updateAvatar(fichier);
      }
      ref.invalidate(currentProfileProvider);
      _signaler(fichier == null ? 'Photo retirée' : 'Photo mise à jour');
    } catch (e) {
      _signaler('Photo impossible à enregistrer : $e', erreur: true);
    } finally {
      if (mounted) setState(() => _photoEnCours = false);
    }
  }

  Future<void> _enregistrer() async {
    final nom = _nomController.text.trim();
    if (nom.isEmpty) {
      _signaler('Le nom affiché ne peut pas être vide', erreur: true);
      return;
    }

    setState(() => _enregistrement = true);
    try {
      await ref.read(profileServiceProvider).updateProfile(
            displayName: nom,
            bio: _bioController.text.trim(),
          );
      // Best-effort : un profil Matrix non recopié ne casse rien dans l'app,
      // seuls les bots verraient encore l'ancien nom.
      try {
        await ref.read(matrixServiceProvider).definirNomAffiche(nom);
      } catch (e) {
        debugPrint('Profil: nom Matrix non mis à jour: $e');
      }
      ref.invalidate(currentProfileProvider);
      if (!mounted) return;
      _signaler('Profil enregistré');
      await Navigator.of(context).maybePop();
    } catch (e) {
      _signaler('Enregistrement impossible : $e', erreur: true);
    } finally {
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  void _signaler(String message, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            erreur ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }
}
