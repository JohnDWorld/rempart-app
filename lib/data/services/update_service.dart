import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/update_constants.dart';
import '../../core/plateforme.dart';

/// Une version disponible sur le serveur de mises à jour.
@immutable
class VersionDisponible {
  const VersionDisponible({
    required this.versionCode,
    required this.versionName,
    required this.url,
    required this.sha256,
    required this.taille,
    required this.notes,
  });

  factory VersionDisponible.fromJson(Map<String, dynamic> json) =>
      VersionDisponible(
        versionCode: (json['versionCode'] as num).toInt(),
        versionName: (json['versionName'] as String?) ?? '',
        url: json['url'] as String,
        sha256: ((json['sha256'] as String?) ?? '').toLowerCase(),
        taille: (json['size'] as num?)?.toInt() ?? 0,
        notes: (json['notes'] as String?) ?? '',
      );

  final int versionCode;
  final String versionName;
  final String url;
  final String sha256;
  final int taille;
  final String notes;
}

/// Avancement d'un téléchargement en cours.
@immutable
class ProgressionMaj {
  const ProgressionMaj({
    required this.octets,
    required this.total,
    required this.enPause,
  });

  final int octets;

  /// Taille annoncée, ou -1 tant que le serveur ne l'a pas dite.
  final int total;

  /// En pause vaut « en cours » pour l'utilisateur : le système reprendra
  /// seul, il n'a rien à faire de plus.
  final bool enPause;

  /// Fraction téléchargée, ou null si la taille reste inconnue : mieux vaut
  /// pas de pourcentage qu'un pourcentage faux.
  double? get fraction =>
      total > 0 ? (octets / total).clamp(0.0, 1.0) : null;
}

/// Mise à jour de l'application hors magasin, sur Android uniquement.
///
/// Le service ne fait que trois choses : lire le manifeste publié par le
/// serveur, télécharger l'APK en vérifiant son empreinte, et passer la main à
/// l'installateur d'Android. Rien n'est jamais installé sans que l'utilisateur
/// le voie : Android affiche son propre écran de confirmation, et c'est lui qui
/// décide.
///
/// iOS n'est pas concerné : Apple interdit toute installation hors App Store,
/// donc [disponible] y est toujours faux.
class UpdateService {
  UpdateService._();

  static final UpdateService instance = UpdateService._();

  static const _canal = MethodChannel('rempart/maj');
  static const _cleDerniereVerif = 'maj_derniere_verification';

  /// La mise à jour intégrée a-t-elle un sens sur cette plateforme et dans ce
  /// build ?
  bool get disponible => UpdateConstants.actif && estAndroid;

  /// Interroge le serveur et renvoie la version publiée si elle est plus
  /// récente que celle installée, `null` sinon.
  ///
  /// Ne lève pas : un serveur injoignable est le cas courant (hors du réseau
  /// Tailscale), et ne doit pas se transformer en erreur à l'écran.
  Future<VersionDisponible?> chercherMiseAJour() async {
    if (!disponible) return null;
    try {
      final manifeste = await _lireManifeste();
      if (manifeste == null) return null;
      final info = await PackageInfo.fromPlatform();
      final actuelle = int.tryParse(info.buildNumber) ?? 0;
      return manifeste.versionCode > actuelle ? manifeste : null;
    } catch (e) {
      debugPrint('[maj] vérification impossible : $e');
      return null;
    }
  }

  /// Comme [chercherMiseAJour], mais au plus une fois par
  /// [UpdateConstants.intervalle]. Appelée au lancement de l'application.
  ///
  /// La fenêtre ne se referme que sur un résultat que l'utilisateur n'a pas à
  /// voir : rien de neuf, ou serveur injoignable. **Une version trouvée ne la
  /// consomme pas**, car rien ne garantit qu'on la lui aura montrée : l'app
  /// peut avoir démarré derrière un écran verrouillé, ou être tuée avant que
  /// la boîte n'apparaisse. La consommer là reviendrait à cacher pendant six
  /// heures une mise à jour prête, sans que personne l'ait jamais vue.
  ///
  /// C'est [reporterVerification] qui referme la fenêtre, une fois la
  /// proposition faite et déclinée.
  Future<VersionDisponible?> chercherSiEcheance() async {
    if (!disponible) return null;
    final prefs = await SharedPreferences.getInstance();
    final dernier = prefs.getInt(_cleDerniereVerif);
    final echu = doitVerifier(
      derniere: dernier == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(dernier),
      maintenant: DateTime.now(),
    );
    if (!echu) return null;

    final version = await chercherMiseAJour();
    if (version == null) await reporterVerification();
    return version;
  }

  /// Referme la fenêtre de vérification pour [UpdateConstants.intervalle].
  ///
  /// Appelée quand l'utilisateur a vu la proposition et l'a déclinée : sans
  /// cela, elle reviendrait à chaque retour dans l'application.
  Future<void> reporterVerification() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_cleDerniereVerif, DateTime.now().millisecondsSinceEpoch);
  }

  Future<VersionDisponible?> _lireManifeste() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final requete = await client.getUrl(Uri.parse(UpdateConstants.manifestUrl));
      final reponse = await requete.close();
      if (reponse.statusCode != 200) {
        debugPrint('[maj] manifeste : HTTP ${reponse.statusCode}');
        return null;
      }
      final corps = await reponse.transform(utf8.decoder).join();
      return VersionDisponible.fromJson(
        jsonDecode(corps) as Map<String, dynamic>,
      );
    } finally {
      client.close();
    }
  }

  /// Confie le téléchargement au système, qui le poursuit application fermée.
  ///
  /// Le téléchargement vivait ici : verrouiller l'écran ou quitter Rempart
  /// tuait le processus, et 87 Mo repartaient de zéro. Avec plusieurs versions
  /// de retard, la mise à jour devenait impossible à mener à son terme.
  ///
  /// `DownloadManager` continue seul, reprend après une coupure réseau et
  /// affiche sa propre progression. À la fin, le côté natif vérifie
  /// l'empreinte et pose une notification : l'installation reste un geste
  /// volontaire.
  ///
  /// Rend faux si l'APK était déjà là, vérifié : rien n'a été téléchargé et
  /// l'invitation à installer est déjà posée.
  Future<bool> telechargerEnFond(VersionDisponible version) async {
    final id = await _canal.invokeMethod<int>('telechargerEnFond', {
      'url': version.url,
      'sha256': version.sha256,
      'versionCode': version.versionCode,
      'versionNom': version.versionName,
    });
    return (id ?? -1) >= 0;
  }

  /// Chemin de l'APK de cette version s'il attend déjà, vérifié, sinon null.
  ///
  /// C'est ce qui permet à l'écran de proposer « Installer » plutôt que
  /// « Télécharger ». Sans cela, l'installation ne tenait qu'à la
  /// notification : balayée par mégarde, elle laissait 104 Mo sur le téléphone
  /// sans aucun moyen de s'en servir, et le seul recours était de tout
  /// retélécharger.
  Future<String?> cheminApkPret(VersionDisponible version) async {
    if (!disponible) return null;
    try {
      return await _canal.invokeMethod<String>('apkPret', {
        'versionCode': version.versionCode,
      });
    } catch (e) {
      debugPrint('[maj] état du téléchargement inconnu : $e');
      return null;
    }
  }

  /// Où en est le téléchargement, ou null s'il n'y en a pas en cours.
  ///
  /// La question est posée au système plutôt qu'à un drapeau que l'application
  /// tiendrait : `DownloadManager` continue application fermée, et un drapeau
  /// serait faux dès le premier redémarrage. L'écran afficherait alors
  /// « Télécharger » sur un transfert déjà en route, invitant à le lancer une
  /// seconde fois.
  Future<ProgressionMaj?> progression() async {
    if (!disponible) return null;
    try {
      final brut = await _canal.invokeMapMethod<String, dynamic>('progressionMaj');
      if (brut == null) return null;
      return ProgressionMaj(
        octets: (brut['octets'] as num?)?.toInt() ?? 0,
        total: (brut['total'] as num?)?.toInt() ?? -1,
        enPause: brut['enPause'] as bool? ?? false,
      );
    } catch (e) {
      debugPrint('[maj] progression inconnue : $e');
      return null;
    }
  }

  /// Ouvre l'installateur d'Android sur un APK déjà téléchargé.
  Future<void> installer(String chemin) =>
      _canal.invokeMethod<void>('installer', {'chemin': chemin});

  /// Efface les APK dont la version est déjà installée.
  ///
  /// Rien ne les supprimait : chaque mise à jour laissait une centaine de
  /// mega-octets derrière elle, indéfiniment. Appelée au lancement, seul
  /// moment où l'on sait avec certitude qu'un APK a fait son office (ou ne le
  /// fera jamais) : l'application tourne, et sa version le dit.
  Future<void> purgerAnciens() async {
    if (!disponible) return;
    try {
      final info = await PackageInfo.fromPlatform();
      await _canal.invokeMethod<void>('purger', {
        'versionInstallee': int.tryParse(info.buildNumber) ?? 0,
      });
    } catch (e) {
      debugPrint('[maj] purge impossible : $e');
    }
  }

  /// L'application a-t-elle le droit d'installer une autre application ?
  ///
  /// Android 8 et suivants demandent cette autorisation par application ; sans
  /// elle l'installateur s'ouvre sur un écran vide.
  Future<bool> peutInstaller() async {
    if (!disponible) return false;
    return await _canal.invokeMethod<bool>('peutInstaller') ?? false;
  }

  /// Ouvre le réglage système « installer des applications inconnues ».
  Future<void> ouvrirReglageInstallation() =>
      _canal.invokeMethod<void>('ouvrirReglageInstallation');
}
