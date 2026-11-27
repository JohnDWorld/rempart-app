import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../../../data/services/compression_image.dart';
import '../../../data/services/compression_video.dart';

/// Aperçu d'une pièce jointe avant envoi, avec sa légende.
///
/// Sans cet écran intermédiaire, joindre une image obligeait à envoyer un
/// second message pour dire ce qu'on en attend, que le destinataire devait
/// rattacher de tête.
/// Ce que l'utilisateur a décidé dans la feuille d'envoi.
@immutable
class ChoixEnvoi {
  const ChoixEnvoi({required this.legende, required this.hauteQualite});

  final String legende;

  /// Vrai : photos et vidéos partent telles quelles. Faux : elles sont
  /// allégées (vidéos en 720p).
  final bool hauteQualite;
}

/// Aperçu des médias choisis, légende commune, et choix de la qualité.
class FeuilleLegende extends StatefulWidget {
  const FeuilleLegende({
    required this.fichiers,
    super.key,
    this.limiteEnvoi,
    this.legende,
  });

  final List<matrix.MatrixFile> fichiers;

  /// Légende proposée d'office (le texte joint à un partage).
  final String? legende;

  /// Taille maximale acceptée par le serveur, si elle est connue. Une vidéo
  /// au-dessus est refusée à l'envoi, et rien ne le disait avant d'essayer.
  final int? limiteEnvoi;

  @override
  State<FeuilleLegende> createState() => _FeuilleLegendeState();
}

class _FeuilleLegendeState extends State<FeuilleLegende> {
  late final _controller = TextEditingController(text: widget.legende);
  bool _hd = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<matrix.MatrixFile> get _fichiers => widget.fichiers;

  bool _estImage(matrix.MatrixFile f) => f.mimeType.startsWith('image/');

  /// Une vidéo s'allège avant l'envoi, là où l'appareil sait l'encoder.
  bool _videoAllegeable(matrix.MatrixFile f) =>
      f.mimeType.startsWith('video/') && CompressionVideo.disponible;

  bool get _avecVideo => _fichiers.any(_videoAllegeable);

  /// L'interrupteur ne s'affiche que s'il change quelque chose : un document
  /// part tel quel de toute façon.
  bool get _qualiteEnJeu => _fichiers.any(
        (f) => (_estImage(f) && f.size > 300 * 1024) || _videoAllegeable(f),
      );

  int get _poidsTotal => _fichiers.fold(0, (total, f) => total + f.size);

  /// Fichiers que le serveur refusera.
  ///
  /// Une vidéo allégée n'en fait pas partie : la compression la ramène sous
  /// la limite (ou dit, à l'envoi, qu'elle est trop longue). En qualité
  /// d'origine, elle part telle quelle et dépasse.
  List<matrix.MatrixFile> get _tropLourds {
    final limite = widget.limiteEnvoi;
    if (limite == null) return const [];
    return _fichiers
        .where((f) => f.size > limite && (_hd || !_videoAllegeable(f)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nombre = _fichiers.length;
    final photoSeule = nombre == 1 && _estImage(_fichiers.first);

    return Padding(
      // Remonter au-dessus du clavier : la feuille est en bas de l'écran.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Le haut cède la place quand le clavier monte, la légende et
              // l'envoi jamais : le clavier des emojis de Gboard, plus haut
              // que celui des lettres, les recouvrait (2026-11-27). Une photo
              // seule se réduit, le reste défile, à parts égales.
              if (photoSeule) Flexible(child: _apercuUnique(_fichiers.first)),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Un seul média : on le montre en grand, c'est ce
                      // qu'on regarde. Plusieurs : une bande de vignettes,
                      // qui dit le nombre et l'ordre sans écraser le reste
                      // de la feuille.
                      if (nombre == 1 && !photoSeule)
                        _apercuUnique(_fichiers.first)
                      else if (nombre > 1)
                        SizedBox(
                          height: 96,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: nombre,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, i) =>
                                _vignette(_fichiers[i]),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        nombre == 1
                            ? CompressionImage.poidsLisible(_poidsTotal)
                            : '$nombre éléments · '
                                '${CompressionImage.poidsLisible(_poidsTotal)}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                      if (_tropLourds.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        // Dit avant d'engager l'envoi : le serveur
                        // refuserait, et l'utilisateur n'aurait qu'une
                        // pastille rouge sans cause.
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: theme.colorScheme.onErrorContainer,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  (_tropLourds.length == _fichiers.length
                                          ? 'Trop volumineux pour le serveur '
                                              '(maximum '
                                              '${CompressionImage.poidsLisible(widget.limiteEnvoi!)}). '
                                              "L'envoi échouera."
                                          : '${_tropLourds.length} élément(s) dépassent '
                                              '${CompressionImage.poidsLisible(widget.limiteEnvoi!)} '
                                              'et seront refusés.') +
                                      // Une vidéo n'est trop lourde ici qu'en
                                      // qualité d'origine : dire la sortie.
                                      (_tropLourds.any(_videoAllegeable)
                                          ? " Sans la qualité d'origine, la vidéo "
                                              'serait allégée.'
                                          : ''),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onErrorContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_qualiteEnJeu) ...[
                        const SizedBox(height: 4),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: _hd,
                          onChanged: (v) => setState(() => _hd = v),
                          title: const Text("Qualité d'origine (HD)"),
                          subtitle: Text(
                            switch ((_hd, _avecVideo)) {
                              (true, false) =>
                                'Les photos partent telles quelles, sans perte.',
                              (true, true) => 'Envoyé tel quel, sans perte.',
                              (false, false) =>
                                'Les photos sont allégées : plus '
                                    "rapide, et indiscernable à l'écran.",
                              (false, true) =>
                                "Allégé avant l'envoi (vidéos en "
                                    '720p) : plus rapide et bien plus léger.',
                            },
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                autofocus: true,
                maxLines: 3,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: nombre > 1
                      ? "Une légende pour l'ensemble (facultatif)"
                      : 'Ajouter une légende (facultatif)',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Annuler'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(
                      context,
                      ChoixEnvoi(
                        legende: _controller.text,
                        hauteQualite: _hd,
                      ),
                    ),
                    icon: const Icon(Icons.send),
                    label: Text(
                      nombre > 1 ? 'Envoyer ($nombre)' : 'Envoyer',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _apercuUnique(matrix.MatrixFile fichier) {
    if (!_estImage(fichier)) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.insert_drive_file, size: 32),
        title: Text(
          fichier.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 260),
        child: Image.memory(
          fichier.bytes,
          fit: BoxFit.contain,
          width: double.infinity,
          // La hauteur affichée ne dépasse jamais 260 : décoder à cette
          // hauteur suffit quel que soit le format, le rapport étant gardé.
          cacheHeight: (260 * MediaQuery.devicePixelRatioOf(context)).round(),
        ),
      ),
    );
  }

  Widget _vignette(matrix.MatrixFile fichier) {
    final theme = Theme.of(context);
    if (!_estImage(fichier)) {
      return Container(
        width: 96,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Icon(
          fichier.mimeType.startsWith('video/')
              ? Icons.videocam_outlined
              : Icons.insert_drive_file,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.memory(
        fichier.bytes,
        width: 96,
        height: 96,
        fit: BoxFit.cover,
        // Quinze photos choisies d'un coup, c'étaient quinze décodages en
        // pleine résolution pour des vignettes de 96 points. Le double de
        // leur côté, pour qu'un recadrage au carré reste net jusqu'à un
        // format 2:1.
        cacheWidth: (2 * 96 * MediaQuery.devicePixelRatioOf(context)).round(),
      ),
    );
  }
}
