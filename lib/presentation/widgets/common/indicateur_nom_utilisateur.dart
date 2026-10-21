import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/utils/verification_nom_utilisateur.dart';

/// Au bout du champ du nom d'utilisateur : une roue pendant la question à la
/// base, une coche verte quand le nom est libre, rien sinon (le refus se dit
/// sous le champ).
Widget? indicateurNomUtilisateur(BuildContext context, EtatNomUtilisateur etat) =>
    switch (etat) {
      EtatNomUtilisateur.verification => const Padding(
          padding: EdgeInsets.all(14),
          child: SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator.adaptive(strokeWidth: 2),
          ),
        ),
      EtatNomUtilisateur.disponible => Icon(
          Icons.check_circle,
          semanticLabel: 'Disponible',
          color: RempartTokens.texteSucces(Theme.of(context).brightness),
        ),
      _ => null,
    };
