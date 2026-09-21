import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/bot_gateway_constants.dart';
import '../../core/utils/appairage_crypto.dart';

/// Connexion d'un appareil par QR code, sans retaper son mot de passe.
///
/// Utilise `package:http` et non `HttpClient` de `dart:io`, contrairement au
/// reste des appels à la passerelle : c'est justement dans un navigateur que
/// cette fonctionnalité sert le plus, et `dart:io` n'y existe pas.
class AppairageService {
  AppairageService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  String get _base => BotGatewayConstants.baseUrl;

  /// Ouvre un appairage côté passerelle et rend de quoi afficher le QR.
  ///
  /// Le secret ne quitte jamais cet appareil autrement que par le code
  /// lui-même : la passerelle n'en reçoit que l'empreinte.
  Future<Appairage> demarrer() async {
    if (_base.isEmpty) {
      throw Exception('BOT_GATEWAY_URL non configuré.');
    }
    final secret = tirerSecret();
    final reponse = await _client
        .post(
          Uri.parse('$_base/v1/pairing/start'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'empreinte': empreinteDe(secret)}),
        )
        .timeout(const Duration(seconds: 12));
    if (reponse.statusCode != 200) {
      throw Exception('Appairage impossible : ${reponse.body}');
    }
    final corps = jsonDecode(reponse.body) as Map<String, dynamic>;
    return Appairage(
      id: corps['id'] as String,
      secret: secret,
      duree: Duration(seconds: (corps['duree'] as num?)?.toInt() ?? 120),
    );
  }

  /// Contenu du QR : de quoi retrouver l'appairage, et lui seul.
  static String contenuQr(Appairage appairage) => jsonEncode({
        'v': 1,
        'id': appairage.id,
        's': secretEnTexte(appairage.secret),
      });

  /// Attend l'approbation, puis ouvre la session sur cet appareil.
  ///
  /// Rend faux si le délai passe sans que personne n'approuve : le code est
  /// alors périmé et il faut en afficher un neuf.
  Future<bool> attendrePuisOuvrirSession(Appairage appairage) async {
    final limite = DateTime.now().add(appairage.duree);
    while (DateTime.now().isBefore(limite)) {
      final reponse = await _client
          .get(Uri.parse('$_base/v1/pairing/poll?id=${appairage.id}'))
          .timeout(const Duration(seconds: 40));

      if (reponse.statusCode == 204) {
        // Personne n'a encore approuvé : la passerelle nous rend la main pour
        // que la requête ne meure pas d'elle-même. On repart attendre.
        continue;
      }
      if (reponse.statusCode == 404) return false;
      if (reponse.statusCode != 200) {
        throw Exception('Appairage interrompu : ${reponse.body}');
      }

      final paquet = (jsonDecode(reponse.body)
          as Map<String, dynamic>)['paquet'] as Map<String, dynamic>;
      final session = jsonDecode(
        utf8.decode(ouvrirPaquet(appairage.secret, paquet)),
      ) as Map<String, dynamic>;
      await _ouvrirSession(session);
      return true;
    }
    return false;
  }

  Future<void> _ouvrirSession(Map<String, dynamic> session) async {
    // Un lien à usage unique, échangé ici contre une vraie session : celle-ci
    // vit et se révoque indépendamment de l'appareil qui a approuvé.
    await Supabase.instance.client.auth.verifyOTP(
      type: OtpType.magiclink,
      tokenHash: session['token_hash'] as String,
    );
  }

  /// Approuve un appairage depuis un appareil déjà connecté.
  ///
  /// Le secret prouve que l'on a vu le code de ses yeux ; le jeton de session,
  /// que l'on est bien le propriétaire du compte. Les deux sont exigés.
  Future<void> approuver(String contenuQrScanne) async {
    final donnees = jsonDecode(contenuQrScanne) as Map<String, dynamic>;
    final jeton = Supabase.instance.client.auth.currentSession?.accessToken;
    if (jeton == null) throw Exception('Vous devez être connecté.');

    final reponse = await _client
        .post(
          Uri.parse('$_base/v1/pairing/approve'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $jeton',
          },
          body: jsonEncode({'id': donnees['id'], 'secret': donnees['s']}),
        )
        .timeout(const Duration(seconds: 15));
    if (reponse.statusCode != 200) {
      throw Exception(reponse.body.isEmpty ? 'refus de la passerelle' : reponse.body);
    }
  }

  /// Ce code vient-il bien de Rempart ?
  ///
  /// Écarte tout de suite les QR du monde extérieur, plutôt que de laisser la
  /// passerelle répondre par une erreur incompréhensible.
  static bool ressembleAUnCodeRempart(String contenu) {
    try {
      final donnees = jsonDecode(contenu);
      return donnees is Map &&
          donnees['v'] == 1 &&
          donnees['id'] is String &&
          donnees['s'] is String;
    } catch (_) {
      return false;
    }
  }
}

/// Un appairage en cours, du côté de l'appareil qui attend.
class Appairage {
  const Appairage({
    required this.id,
    required this.secret,
    required this.duree,
  });

  final String id;

  /// Ne sort d'ici que par le QR affiché à l'écran.
  final Uint8List secret;
  final Duration duree;

  @visibleForTesting
  String get contenuQr => AppairageService.contenuQr(this);
}
