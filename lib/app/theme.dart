import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/plateforme.dart';

/// Jetons de style de Rempart : couleurs, ombres, rayons, espacements.
///
/// Un seul endroit décide de l'apparence. Les écrans lisent ces jetons (ou le
/// `Theme` qui en découle) plutôt que d'écrire des couleurs en dur, sinon une
/// retouche se transforme en chasse au trésor.
///
/// Parti pris : sobre et souverain. La profondeur vient des couches (fond,
/// surface, surface enfoncée) et d'ombres douces, pas de la couleur. Une
/// messagerie chiffrée doit inspirer le calme et la solidité, pas la fête.
abstract class RempartTokens {
  /// Au-delà, on n'est plus sur un téléphone : l'accueil passe à deux
  /// colonnes, la barre d'onglets disparaît, et une feuille qui remonte du bas
  /// cède la place à une fenêtre centrée.
  static const seuilEcranLarge = 900.0;

  // --- Couleurs, thème clair ---------------------------------------------
  /// Fond de page : légèrement bleuté, pour que le blanc des cartes ressorte.
  static const fondClair = Color(0xFFF6F8FB);
  static const surfaceClaire = Color(0xFFFFFFFF);

  /// Surface « enfoncée » : champs de saisie, pastilles, bulles reçues.
  static const surfaceEnfonceeClaire = Color(0xFFEDF1F7);
  static const contourClair = Color(0xFFE3E9F0);
  static const texteClair = Color(0xFF0F172A);
  static const texteSecondaireClair = Color(0xFF64748B);

  // --- Couleurs, thème sombre --------------------------------------------
  static const fondSombre = Color(0xFF0B1220);
  static const surfaceSombre = Color(0xFF141D2E);
  static const surfaceEnfonceeSombre = Color(0xFF1D2839);
  static const contourSombre = Color(0xFF253046);

  /// Fond d'une citation, au-dessus d'une réponse.
  ///
  /// Plus contrastée que `surfaceEnfoncee`, dont elle dérivait : à basse
  /// luminance, l'oeil distingue beaucoup moins deux teintes proches, et le
  /// bloc cité se confondait avec la bulle (rapport 1,14 en sombre). Ce n'est
  /// pas un détail d'esthétique : une citation qu'on ne voit pas ne dit plus à
  /// quoi le message répond.
  static const citationSombre = Color(0xFF2B3A52);
  static const citationClaire = Color(0xFFDCE4EF);
  static const texteSombre = Color(0xFFE8EDF5);
  static const texteSecondaireSombre = Color(0xFF94A3B8);

  // --- Accents ------------------------------------------------------------
  static const bleu = Color(0xFF2563EB);
  static const bleuFonce = Color(0xFF1D4ED8);
  static const bleuClair = Color(0xFF60A5FA);
  static const succes = Color(0xFF16A34A);
  static const alerte = Color(0xFFEA580C);
  static const erreur = Color(0xFFDC2626);

  /// Bleu marine de l'icône de l'application et de la barre du navigateur.
  ///
  /// L'écran de démarrage s'ouvre dessus : c'est la couleur que l'utilisateur
  /// vient de toucher sur son écran d'accueil, et celle que le navigateur
  /// affiche avant que la page ne charge. Un autre bleu faisait une saccade
  /// de couleur à chaque lancement.
  static const marine = Color(0xFF1E3048);

  /// Vert et orange **pour du texte**, un par thème.
  ///
  /// `succes` et `alerte` sont des teintes d'icône et de fond : posés en
  /// texte, ils ne tiennent pas le contraste (3,30:1 et 3,56:1 sur blanc,
  /// quand un petit texte en exige 4,5:1). C'est ce qui laissait chaque écran
  /// choisir son propre vert, et le badge « chiffré », le signal de confiance
  /// de l'application, tombait à 3,2:1 en thème sombre. Valeurs calculées, pas
  /// choisies à l'oeil : 6,70:1 et 6,87:1 sur le fond clair, 10,74:1 et
  /// 8,27:1 sur le fond sombre.
  static Color texteSucces(Brightness luminosite) =>
      luminosite == Brightness.dark
          ? const Color(0xFF4ADE80)
          : const Color(0xFF166534);

  /// Plus foncé que l'orange d'un avertissement ordinaire, et c'est voulu :
  /// posé sur sa propre teinte (un badge « Non chiffré »), `#C2410C` tombait
  /// à 4,10:1. `#9A3412` tient 5,66:1 sur sa teinte à 12 %, 6,87:1 à nu.
  static Color texteAlerte(Brightness luminosite) =>
      luminosite == Brightness.dark
          ? const Color(0xFFFB923C)
          : const Color(0xFF9A3412);

  // --- Rayons -------------------------------------------------------------
  static const rayonChamp = 14.0;
  static const rayonCarte = 18.0;
  static const rayonBulle = 20.0;

  // --- Espacements --------------------------------------------------------
  /// Échelle de 4 : tout espacement de l'app est un multiple, ce qui suffit à
  /// donner un rythme régulier sans y penser.
  static const espaceXs = 4.0;
  static const espaceS = 8.0;
  static const espaceM = 12.0;
  static const espaceL = 16.0;
  static const espaceXl = 24.0;

  // --- Ombres -------------------------------------------------------------
  /// Deux ombres superposées : une large et très diffuse pour l'assise, une
  /// courte et plus dense pour le contact. C'est ce couple qui fait « posé sur
  /// la page » là où une ombre unique fait « autocollant ».
  static List<BoxShadow> ombreDouce(Brightness luminosite) {
    final noir = luminosite == Brightness.dark ? 0.45 : 0.06;
    return [
      BoxShadow(
        color: const Color(0xFF0F172A).withValues(alpha: noir),
        blurRadius: 24,
        offset: const Offset(0, 8),
      ),
      BoxShadow(
        color: const Color(0xFF0F172A).withValues(alpha: noir * 0.7),
        blurRadius: 6,
        offset: const Offset(0, 2),
      ),
    ];
  }

  /// Ombre discrète des éléments posés à même la liste (lignes, pastilles).
  static List<BoxShadow> ombreLegere(Brightness luminosite) => [
        BoxShadow(
          color: const Color(0xFF0F172A)
              .withValues(alpha: luminosite == Brightness.dark ? 0.35 : 0.04),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ];

  /// Palette des avatars sans photo : teintes désaturées, lisibles en clair
  /// comme en sombre, et stables pour une même personne (index = hash du nom).
  static const avatars = <(Color, Color)>[
    (Color(0xFFDBEAFE), Color(0xFF1D4ED8)),
    (Color(0xFFDCFCE7), Color(0xFF15803D)),
    (Color(0xFFFEF3C7), Color(0xFFB45309)),
    (Color(0xFFFCE7F3), Color(0xFFBE185D)),
    (Color(0xFFE0E7FF), Color(0xFF4338CA)),
    (Color(0xFFCCFBF1), Color(0xFF0F766E)),
    (Color(0xFFFFE4E6), Color(0xFFBE123C)),
  ];

  /// Encre du nom d'un expéditeur, au-dessus de sa bulle dans un groupe.
  ///
  /// En clair, c'est celle de sa pastille : le nom et l'avatar se répondent.
  /// En sombre, elle ne tient plus : ces encres sont faites pour le fond pastel
  /// des pastilles, et sur une bulle reçue sombre elles tombaient entre 2,13 et
  /// 3,36:1, sous le seuil de 4,5. Même teinte, en plus clair (5,65 à 10,10:1).
  static Color encreNom(int index, Brightness luminosite) {
    final i = index % avatars.length;
    return luminosite == Brightness.dark ? _encresNomSombre[i] : avatars[i].$2;
  }

  static const _encresNomSombre = <Color>[
    Color(0xFF60A5FA),
    Color(0xFF4ADE80),
    Color(0xFFFBBF24),
    Color(0xFFF472B6),
    Color(0xFF818CF8),
    Color(0xFF2DD4BF),
    Color(0xFFFB7185),
  ];
}

/// Thème de l'application Rempart.
abstract class RempartTheme {
  /// Nom de la famille embarquée (voir `pubspec.yaml`).
  ///
  /// Police embarquée et non téléchargée : l'app doit démarrer et s'afficher
  /// sans réseau, ce qui exclut `google_fonts` et son chargement à la volée.
  static const police = 'Inter';

  // Conservés : d'anciens écrans les référencent encore.
  static const Color primaryColor = RempartTokens.bleu;
  static const Color primaryDarkColor = RempartTokens.bleuFonce;
  static const Color secondaryColor = Color(0xFF0EA5E9);
  static const Color errorColor = RempartTokens.erreur;
  static const Color successColor = RempartTokens.succes;
  static const Color warningColor = RempartTokens.alerte;

  static ThemeData get light => _construire(Brightness.light);
  static ThemeData get dark => _construire(Brightness.dark);

  static ThemeData _construire(Brightness luminosite) {
    final sombre = luminosite == Brightness.dark;

    final fond = sombre ? RempartTokens.fondSombre : RempartTokens.fondClair;
    final surface =
        sombre ? RempartTokens.surfaceSombre : RempartTokens.surfaceClaire;
    final enfoncee = sombre
        ? RempartTokens.surfaceEnfonceeSombre
        : RempartTokens.surfaceEnfonceeClaire;
    final contour =
        sombre ? RempartTokens.contourSombre : RempartTokens.contourClair;
    final texte = sombre ? RempartTokens.texteSombre : RempartTokens.texteClair;
    final texteSecondaire = sombre
        ? RempartTokens.texteSecondaireSombre
        : RempartTokens.texteSecondaireClair;
    final accent = sombre ? RempartTokens.bleuClair : RempartTokens.bleu;

    final couleurs = ColorScheme(
      brightness: luminosite,
      primary: accent,
      onPrimary: sombre ? const Color(0xFF06122A) : Colors.white,
      primaryContainer:
          sombre ? const Color(0xFF1E3A8A) : const Color(0xFFDBEAFE),
      onPrimaryContainer:
          sombre ? const Color(0xFFDBEAFE) : RempartTokens.bleuFonce,
      secondary: secondaryColor,
      onSecondary: Colors.white,
      // Sans ces deux lignes, `secondaryContainer` retombe sur `secondary` et
      // `onSecondaryContainer` sur `onSecondary` : un bleu ciel vif avec du
      // blanc dessus, soit 2,77:1, sous les 4,5:1 d'un petit texte. C'est la
      // pastille « Rempart » des agents livres qui le portait. Un conteneur
      // est une teinte SOURDE de sa couleur, jamais la couleur elle-meme.
      secondaryContainer:
          sombre ? const Color(0xFF0C4A6E) : const Color(0xFFBAE6FD),
      onSecondaryContainer:
          sombre ? const Color(0xFFBAE6FD) : const Color(0xFF075985),
      // Un rouge plus clair en thème sombre : `erreur` n'y tenait que 3,49:1
      // sur les surfaces, sous les 4,5:1 d'un petit texte, et c'est le rouge
      // des actions qui détruisent (« Supprimer », « Bloquer »). Le texte posé
      // dessus passe alors au rouge très foncé, le blanc n'y tenant plus
      // (2,77:1 contre 5,84:1).
      error: sombre ? const Color(0xFFF87171) : RempartTokens.erreur,
      onError: sombre ? const Color(0xFF450A0A) : Colors.white,
      surface: surface,
      onSurface: texte,
      surfaceContainerLowest: fond,
      surfaceContainerLow: fond,
      surfaceContainer: enfoncee,
      surfaceContainerHigh: enfoncee,
      surfaceContainerHighest: enfoncee,
      onSurfaceVariant: texteSecondaire,
      // `outline` sert de gris à lire (légendes, sous-titres, icônes ternes) :
      // les écrans y puisent naturellement pour du texte secondaire. Le lui
      // faire porter la couleur des filets le rendait illisible, un trait de
      // 1 px n'ayant pas à passer les seuils de contraste d'un texte. Les
      // bordures s'appuient sur `outlineVariant`, et sur `contour` dans les
      // thèmes de widgets ci-dessous.
      outline: texteSecondaire,
      outlineVariant: contour,
      shadow: const Color(0xFF0F172A),
    );

    final typo = _typographie(texte, texteSecondaire);

    return ThemeData(
      useMaterial3: true,
      brightness: luminosite,
      colorScheme: couleurs,
      scaffoldBackgroundColor: fond,
      canvasColor: fond,
      fontFamily: police,
      textTheme: typo,
      // iOS ne connaît pas l'onde de Material : un toucher y assombrit
      // brièvement ce qu'on presse, sans cercle qui s'étend. L'étincelle
      // d'Android 12, sur un iPhone, signalait d'emblée une application
      // venue d'ailleurs.
      splashFactory:
          estIOS ? NoSplash.splashFactory : InkSparkle.splashFactory,

      appBarTheme: AppBarTheme(
        backgroundColor: fond,
        foregroundColor: texte,
        surfaceTintColor: Colors.transparent,
        // Centré sur iOS, où c'est la règle de toute barre de navigation ;
        // à gauche ailleurs, comme le veut Material.
        centerTitle: estIOS,
        titleSpacing: RempartTokens.espaceL,
        elevation: 0,
        // L'ombre n'apparaît qu'au défilement : la barre semble alors se
        // détacher du contenu qui glisse dessous.
        scrolledUnderElevation: 3,
        shadowColor:
            const Color(0xFF0F172A).withValues(alpha: sombre ? 0.6 : 0.12),
        titleTextStyle: typo.titleLarge,
        systemOverlayStyle:
            sombre ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),

      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RempartTokens.rayonCarte),
          side: BorderSide(color: contour),
        ),
      ),

      listTileTheme: ListTileThemeData(
        iconColor: texteSecondaire,
        titleTextStyle: typo.titleMedium,
        subtitleTextStyle: typo.bodyMedium?.copyWith(color: texteSecondaire),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: RempartTokens.espaceL,
          vertical: RempartTokens.espaceXs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RempartTokens.rayonChamp),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: couleurs.onPrimary,
          elevation: 0,
          minimumSize: const Size(0, 52),
          padding:
              const EdgeInsets.symmetric(horizontal: RempartTokens.espaceXl),
          textStyle: typo.titleMedium,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(RempartTokens.rayonChamp),
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          textStyle: typo.titleMedium,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(RempartTokens.rayonChamp),
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          foregroundColor: texte,
          side: BorderSide(color: contour),
          textStyle: typo.titleMedium,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(RempartTokens.rayonChamp),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: typo.titleMedium,
          padding: const EdgeInsets.symmetric(
            horizontal: RempartTokens.espaceL,
            vertical: RempartTokens.espaceS,
          ),
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: couleurs.onPrimary,
        elevation: 4,
        focusElevation: 4,
        hoverElevation: 6,
        highlightElevation: 8,
        shape: const CircleBorder(),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: enfoncee,
        hintStyle: typo.bodyLarge?.copyWith(color: texteSecondaire),
        labelStyle: typo.bodyMedium?.copyWith(color: texteSecondaire),
        border: _bordure(Colors.transparent),
        enabledBorder: _bordure(Colors.transparent),
        focusedBorder: _bordure(accent, epaisseur: 1.6),
        errorBorder: _bordure(RempartTokens.erreur),
        focusedErrorBorder: _bordure(RempartTokens.erreur, epaisseur: 1.6),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: RempartTokens.espaceL,
          vertical: RempartTokens.espaceL,
        ),
      ),

      dividerTheme: DividerThemeData(
        color: contour,
        thickness: 1,
        space: 1,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            sombre ? const Color(0xFF243349) : const Color(0xFF1E293B),
        contentTextStyle: typo.bodyMedium?.copyWith(color: Colors.white),
        elevation: 6,
        insetPadding: const EdgeInsets.all(RempartTokens.espaceL),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RempartTokens.rayonChamp),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        titleTextStyle: typo.headlineSmall,
        contentTextStyle: typo.bodyLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RempartTokens.rayonCarte + 4),
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        textStyle: typo.bodyLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RempartTokens.rayonChamp),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: enfoncee,
        side: BorderSide.none,
        labelStyle: typo.labelLarge,
        shape: const StadiumBorder(),
      ),

      // La piste d'une barre de progression suivait `secondaryContainer`,
      // c'est-a-dire le bleu ciel vif : 1,86:1 contre le remplissage en clair
      // et 1,09:1 en sombre, ou les deux moities avaient quasiment la meme
      // luminosite. On ne voyait plus ce qui etait telecharge.
      //
      // La piste prend donc la teinte du remplissage, en sourdine : meme
      // famille, deux niveaux d'ecart, 3,64:1 en clair et 4,07:1 en sombre.
      // Au-dela de 3:1, un element graphique porteur d'information se
      // distingue (WCAG 1.4.11).
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor:
            sombre ? const Color(0xFF1E3A8A) : const Color(0xFFBFDBFE),
        circularTrackColor: Colors.transparent,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (etats) => etats.contains(WidgetState.selected) ? Colors.white : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (etats) => etats.contains(WidgetState.selected) ? accent : null,
        ),
      ),

      // Glissement latéral façon iOS sur toutes les plateformes : plus doux que
      // la montée verticale de Material, et cohérent avec la version iOS.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static OutlineInputBorder _bordure(Color couleur, {double epaisseur = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(RempartTokens.rayonChamp),
      borderSide: couleur == Colors.transparent
          ? BorderSide.none
          : BorderSide(color: couleur, width: epaisseur),
    );
  }

  /// Échelle typographique.
  ///
  /// `height` explicite partout : la hauteur de ligne par défaut de Material
  /// tasse les titres et aère trop les libellés courts.
  static TextTheme _typographie(Color texte, Color secondaire) {
    TextStyle style(double taille, FontWeight graisse, double hauteur,
        {Color? couleur, double espacement = 0}) {
      return TextStyle(
        fontFamily: police,
        fontSize: taille,
        fontWeight: graisse,
        height: hauteur,
        letterSpacing: espacement,
        color: couleur ?? texte,
      );
    }

    return TextTheme(
      headlineLarge: style(28, FontWeight.w700, 1.2, espacement: -0.5),
      headlineMedium: style(24, FontWeight.w700, 1.25, espacement: -0.4),
      headlineSmall: style(20, FontWeight.w600, 1.3, espacement: -0.2),
      titleLarge: style(20, FontWeight.w600, 1.3, espacement: -0.2),
      titleMedium: style(16, FontWeight.w600, 1.35, espacement: -0.1),
      titleSmall: style(14, FontWeight.w600, 1.4),
      bodyLarge: style(15.5, FontWeight.w400, 1.45),
      bodyMedium: style(14, FontWeight.w400, 1.45),
      bodySmall: style(12.5, FontWeight.w400, 1.4, couleur: secondaire),
      labelLarge: style(14, FontWeight.w500, 1.3),
      labelMedium: style(12.5, FontWeight.w500, 1.3),
      labelSmall: style(11.5, FontWeight.w500, 1.2, couleur: secondaire),
    );
  }
}

/// Couleurs de la citation affichée au-dessus d'une réponse.
///
/// Rassemblées ici parce qu'elles dépendent du fond sur lequel elles
/// atterrissent, et que ce fond change trois fois : la bulle colorée de
/// l'expéditeur, et la bulle neutre du destinataire dans chacun des deux
/// thèmes. Les choisir au fil du widget a déjà produit deux fois une citation
/// illisible, dont une invisible : dans sa propre bulle, le fond valait
/// `primary` par-dessus `primary`, donc exactement la couleur de la bulle.
///
/// Les rapports de contraste obtenus sont verrouillés par
/// `test/contraste_citation_test.dart`.
class CouleursCitation {
  const CouleursCitation({
    required this.fond,
    required this.nom,
    required this.texte,
    required this.barre,
  });

  /// Choisit les quatre couleurs pour le contexte donné.
  factory CouleursCitation.pour({
    required bool estLaMienne,
    required ColorScheme schema,
    required Brightness luminosite,
  }) {
    if (estLaMienne) {
      // Un voile SOMBRE, et non un éclaircissement : sur une bulle déjà
      // colorée, assombrir détache le bloc et fait remonter le texte clair
      // d'un même geste, là où l'éclaircir gagnerait l'un en perdant l'autre.
      return CouleursCitation(
        fond: Colors.black.withAlpha(64),
        nom: schema.onPrimary,
        texte: schema.onPrimary.withAlpha(230),
        barre: schema.onPrimary,
      );
    }
    final sombre = luminosite == Brightness.dark;
    return CouleursCitation(
      fond:
          sombre ? RempartTokens.citationSombre : RempartTokens.citationClaire,
      // Le bleu de marque ne tient sur aucun de ces deux fonds : trop sombre
      // sur le fond sombre, trop clair sur le fond clair. Chaque thème prend
      // donc la déclinaison qui s'en détache.
      nom: sombre ? RempartTokens.bleuClair : RempartTokens.bleuFonce,
      texte: schema.onSurface.withAlpha(217),
      barre: sombre ? RempartTokens.bleuClair : RempartTokens.bleu,
    );
  }

  final Color fond;
  final Color nom;
  final Color texte;
  final Color barre;
}
