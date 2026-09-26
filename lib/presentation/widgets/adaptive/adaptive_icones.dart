import 'package:flutter/material.dart';

import '../../../core/plateforme.dart';

/// Flèche de retour de la plateforme, centrée dans son carré.
///
/// `Icons.adaptive.arrow_back` rend sur iOS `arrow_back_ios`, dont le chevron
/// n'occupe que la moitié gauche de son carré (de 0 à 11,7 sur 24) : posé
/// dans une pastille ronde, il paraît décalé vers la gauche.
/// `arrow_back_ios_new` est le même chevron, centré.
IconData get iconeRetour =>
    estIOS ? Icons.arrow_back_ios_new : Icons.arrow_back;
