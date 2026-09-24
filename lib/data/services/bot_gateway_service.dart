import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/bot_gateway_constants.dart';
import '../models/bot.dart';
import '../models/user_bot.dart';

/// Erreur renvoyée par la gateway, avec son code HTTP.
///
/// `toString` ne rend que le message du serveur : celui-ci est déjà rédigé pour
/// l'utilisateur (« le nom doit se terminer par « bot » », « ce nom est déjà
/// pris »), et tous les écrans l'interpolent directement dans une SnackBar. Le
/// préfixer d'« Exception: Gateway 400 » ne ferait que le rendre illisible.
class BotGatewayException implements Exception {
  BotGatewayException(this.statusCode, String corps)
      : message = _lisible(corps, statusCode);

  final int statusCode;
  final String message;

  /// Longueur au-delà de laquelle un message n'est plus un message.
  static const _maxLongueur = 300;

  /// Réduit un corps de réponse à quelque chose de montrable.
  ///
  /// La gateway renvoie du texte court et déjà rédigé, mais rien ne le
  /// garantit : un proxy en amont peut répondre une page HTML, et un plantage
  /// non rattrapé une trace d'appels entière. Les afficher tels quels
  /// remplirait l'écran d'un charabia où l'utilisateur ne peut rien lire.
  static String _lisible(String corps, int statusCode) {
    var texte = corps.trim();
    if (texte.isEmpty) return 'erreur $statusCode';

    // Réponse JSON : garder le champ de message s'il existe.
    if (texte.startsWith('{')) {
      try {
        final json = jsonDecode(texte);
        if (json is Map) {
          for (final cle in ['error', 'message', 'detail']) {
            final valeur = json[cle];
            if (valeur is String && valeur.trim().isNotEmpty) {
              texte = valeur.trim();
              break;
            }
          }
        }
      } catch (_) {
        // Pas du JSON valide : on garde le texte tel quel.
      }
    }

    // Page HTML d'un proxy : illisible telle quelle, on ne garde que le texte.
    if (texte.contains('<') && texte.contains('>')) {
      texte = texte.replaceAll(RegExp('<[^>]*>'), ' ');
    }
    texte = texte.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (texte.isEmpty) return 'erreur $statusCode';

    return texte.length <= _maxLongueur
        ? texte
        : '${texte.substring(0, _maxLongueur)}...';
  }

  /// Le nom demandé est déjà pris (409), cas courant et non fautif.
  bool get estDejaPris => statusCode == 409;

  @override
  String toString() => message;
}

/// Client de la Bot Gateway (API des bots utilisateurs).
///
/// Chaque appel est authentifié par le JWT Supabase de l'utilisateur connecté :
/// la gateway en déduit le propriétaire des bots. Passe par `package:http` et
/// non par le `HttpClient` de `dart:io` : celui-ci n'existe pas dans un
/// navigateur, et toute requête y échouait donc en silence. Sur le web,
/// l'utilisateur perdait « Mes bots », l'annuaire, et jusqu'au menu des
/// commandes d'un bot, faute de savoir lesquelles il déclare.
class BotGatewayService {
  /// Lie le compte Matrix courant (`mxid`) au compte Supabase, pour que
  /// BotFather sache quels bots appartiennent à l'utilisateur. Best-effort, à
  /// appeler une fois la session Matrix établie.
  Future<void> linkMatrix(String mxid) async {
    await _request('POST', '/v1/link', <String, dynamic>{'mxid': mxid});
  }

  /// Fait créer le compte Matrix de l'utilisateur courant par la passerelle.
  ///
  /// L'application ne s'inscrit plus elle-même auprès de Synapse. Cette API
  /// devait rester ouverte pour qu'elle le puisse, or elle est joignable par
  /// tout l'internet : un seul appel suffisait à créer un compte sans passer
  /// par Rempart ni par aucune vérification.
  ///
  /// La passerelle, elle, détient le secret partagé de Synapse. Elle crée donc
  /// le compte alors que l'inscription publique est fermée, et seulement après
  /// avoir vérifié, auprès de Supabase, que l'adresse est confirmée.
  ///
  /// L'identifiant n'est PAS envoyé : la passerelle le dérive du jeton. Un
  /// jeton permet de créer son compte, et aucun autre.
  Future<void> provisionMatrixAccount(String motDePasse) async {
    await _request('POST', '/v1/provisionMatrixAccount', <String, dynamic>{
      'password': motDePasse,
    });
  }

  /// Liste les bots de l'utilisateur connecté, avec son quota.
  /// Demande l'effacement des médias d'un groupe qu'on supprime.
  ///
  /// C'est l'app qui fournit la liste : dans une room chiffrée, le `mxc` d'une
  /// pièce jointe vit à l'intérieur du message chiffré, invisible du serveur.
  /// Réservé côté gateway à un administrateur de la room, et à appeler AVANT
  /// de la vider, tant que ce droit est vérifiable.
  ///
  /// Renvoie le nombre de médias effectivement supprimés.
  Future<int> deleteRoomMedia(String roomId, List<String> mxc) async {
    final data = await _request('POST', '/v1/deleteRoomMedia', {
      'room_id': roomId,
      'mxc': mxc,
    });
    return (data['supprimes'] as num?)?.toInt() ?? 0;
  }

  Future<MyBotsList> myBots() async {
    final data = await _request('GET', '/v1/myBots');
    final bots = (data['bots'] as List<dynamic>).cast<Map<String, dynamic>>();
    final quota = data['quota'] as Map<String, dynamic>?;
    return MyBotsList(
      bots: bots.map(UserBot.fromJson).toList(),
      quota: quota == null ? null : BotQuota.fromJson(quota),
    );
  }

  /// Crée un bot et renvoie son token d'API (à afficher une seule fois).
  ///
  /// [username] devient le localpart Matrix (`@agent_bot:domaine`) et doit se
  /// terminer par « bot ». Il est définitif : un localpart Matrix ne se renomme
  /// pas, contrairement à [name] qui n'est que le nom affiché. Omis, le serveur
  /// retombe sur un identifiant tiré au sort.
  Future<CreatedBot> createBot(String name, {String? username}) async {
    final data = await _request(
      'POST',
      '/v1/createBot',
      <String, dynamic>{
        'name': name,
        if (username != null) 'username': username,
      },
    );
    return CreatedBot.fromJson(data);
  }

  /// Régénère le token d'un bot possédé et renvoie le nouveau (à afficher une
  /// seule fois). Le bot et ses conversations sont conservés ; l'ancien token
  /// cesse aussitôt de fonctionner.
  Future<CreatedBot> regenerateToken(String botId) async {
    final data = await _request(
      'POST',
      '/v1/regenerateToken',
      <String, dynamic>{'bot_id': botId},
    );
    return CreatedBot.fromJson(data);
  }

  /// Met à jour la config riche d'un bot (nom, description, commandes).
  /// Ne passe que les champs non nuls. Renvoie le bot à jour.
  Future<UserBot> setBotConfig(
    String botId, {
    String? name,
    String? description,
    List<BotCommand>? commands,
  }) async {
    final body = <String, dynamic>{'bot_id': botId};
    if (name != null) {
      body['name'] = name;
    }
    if (description != null) {
      body['description'] = description;
    }
    if (commands != null) {
      body['commands'] = commands
          .map((c) => <String, dynamic>{
                'command': c.commande,
                'description': c.description,
              })
          .toList();
    }
    final data = await _request('POST', '/v1/setBotConfig', body);
    return UserBot.fromJson(data['bot'] as Map<String, dynamic>);
  }

  /// Définit l'avatar d'un bot à partir d'une URL d'image (téléchargée côté
  /// serveur puis publiée sur le compte Matrix du bot).
  Future<void> setBotAvatar(String botId, String url) async {
    await _request(
      'POST',
      '/v1/setBotAvatar',
      <String, dynamic>{'bot_id': botId, 'url': url},
    );
  }

  /// Révoque et supprime un bot appartenant à l'utilisateur.
  Future<void> deleteBot(String botId) async {
    await _request(
      'POST',
      '/v1/deleteBot',
      <String, dynamic>{'bot_id': botId},
    );
  }

  /// Efface définitivement le compte : bots, compte Matrix, compte Supabase
  /// et avatars.
  ///
  /// Passe par la gateway et non par Supabase directement : seule la clé de
  /// service peut effacer un compte, et elle ne doit pas quitter le serveur.
  /// L'app se contente de présenter son JWT.
  Future<void> deleteAccount() async {
    await _request('POST', '/v1/deleteAccount', <String, dynamic>{});
  }

  /// Rend un bot possédé visible dans l'annuaire public, ou le repasse privé.
  Future<void> setBotVisibility(String botId, {required bool isPublic}) async {
    await _request(
      'POST',
      '/v1/setBotVisibility',
      <String, dynamic>{'bot_id': botId, 'public': isPublic},
    );
  }

  /// Signale un bot public (par son mxid), avec un motif. Un signalement par
  /// utilisateur ; au seuil, les admins sont notifiés.
  Future<void> reportBot(String mxid, String reason) async {
    await _request(
      'POST',
      '/v1/reportBot',
      <String, dynamic>{'mxid': mxid, 'reason': reason},
    );
  }

  /// Annuaire des bots publics (anonyme). Filtre optionnel par nom.
  Future<List<DirectoryBot>> directory({String query = ''}) async {
    final q = query.trim();
    final path = q.isEmpty
        ? '/v1/directory'
        : '/v1/directory?q=${Uri.encodeQueryComponent(q)}';
    final data = await _request('GET', path);
    final bots = (data['bots'] as List<dynamic>).cast<Map<String, dynamic>>();
    return bots.map(DirectoryBot.fromJson).toList();
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) {
      throw Exception('Vous devez être connecté.');
    }
    final base = BotGatewayConstants.baseUrl;
    if (base.isEmpty) {
      throw Exception('BOT_GATEWAY_URL non configuré.');
    }

    final requete = http.Request(method, Uri.parse('$base$path'))
      ..headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      requete.headers['Content-Type'] = 'application/json';
      requete.body = jsonEncode(body);
    }

    final client = http.Client();
    try {
      // Timeout global : la gateway est facultative, elle ne doit jamais figer
      // l'app (ex. appel best-effort au login sur réseau instable).
      final reponse = await http.Response.fromStream(
        await client.send(requete),
      ).timeout(const Duration(seconds: 12));
      if (reponse.statusCode >= 400) {
        throw BotGatewayException(reponse.statusCode, reponse.body);
      }
      return jsonDecode(reponse.body) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }
}
