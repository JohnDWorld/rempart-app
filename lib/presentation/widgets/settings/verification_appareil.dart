import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../../../app/router.dart';
import '../../../data/services/matrix_service.dart';

/// Vérification d'un appareil, des deux côtés du même échange.
///
/// Le même dialogue sert à celui qui demande et à celui qui reçoit : la
/// machine à états du SDK est identique, seul le point d'entrée diffère.
///
/// Ce que cela apporte, et qui manquait : le chiffrement garantit que seuls
/// « les appareils du compte » lisent les messages, sans jamais dire lesquels.
/// Confirmer une connexion établit qu'un appareil donné est bien le nôtre, le
/// signe pour les autres, et lui fait passer les clés de l'historique.
///
/// **Une seule décision est demandée**, « Confirmer la connexion ? », sur
/// l'appareil déjà connu. Le protocole prévoit ensuite une comparaison de
/// symboles, que l'on passe pour l'utilisateur : les deux appareils sont ceux
/// d'une même personne, qui vient de dire oui sur l'un d'eux, et lui faire
/// comparer six pictogrammes entre deux écrans ne lui apprend rien qu'elle ne
/// sache déjà. Le prix est réel et assumé : cette comparaison est ce qui
/// défend l'échange contre un serveur malveillant qui s'interposerait. Ici le
/// serveur est celui de l'utilisateur, et le geste de trop faisait abandonner
/// la connexion bien plus souvent qu'il ne protégeait.
Future<void> ouvrirVerification(
  KeyVerification verification, {
  required bool nousAvonsDemande,
}) {
  // Le Navigator racine par sa clé, et non le contexte de l'appelant.
  //
  // L'écoute des demandes vit dans le `builder` de l'application, donc
  // au-dessus du Navigator créé par GoRouter : `showDialog` y cherchait un
  // Navigator qui n'existe pas et levait « Null check operator used on a null
  // value ». La demande arrivait bien, le SDK la traitait bien, et la fenêtre
  // ne s'ouvrait jamais, sans que rien ne le dise. Vu dans le journal du
  // téléphone le 2026-09-16, après deux jours passés à chercher ailleurs.
  final context = cleNavigateurRacine.currentContext;
  if (context == null) return Future.value();
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _DialogueVerification(
      verification: verification,
      nousAvonsDemande: nousAvonsDemande,
    ),
  );
}

class _DialogueVerification extends StatefulWidget {
  const _DialogueVerification({
    required this.verification,
    required this.nousAvonsDemande,
  });

  final KeyVerification verification;
  final bool nousAvonsDemande;

  @override
  State<_DialogueVerification> createState() => _DialogueVerificationState();
}

class _DialogueVerificationState extends State<_DialogueVerification> {
  bool _occupe = false;

  /// Étapes déjà franchies seules. Le SDK rappelle plusieurs fois pour un même
  /// état : sans ce garde, la même réponse partirait en double et le serveur
  /// interromprait l'échange.
  final _franchies = <KeyVerificationState>{};

  @override
  void initState() {
    super.initState();
    // `onUpdate` est un unique rappel, pas un flux : le SDK n'accepte qu'un
    // observateur, et c'est lui qui mène l'échange. Ce dialogue ne fait que
    // montrer où il en est.
    widget.verification.onUpdate = () {
      _poursuivreSeul();
      if (mounted) setState(() {});
    };
    // L'échange peut déjà être plus loin que l'ouverture du dialogue.
    _poursuivreSeul();
  }

  @override
  void dispose() {
    widget.verification.onUpdate = null;
    super.dispose();
  }

  /// Franchit les étapes qui n'appellent aucune décision.
  ///
  /// Le choix de la méthode et la comparaison des symboles n'en sont pas :
  /// l'utilisateur a déjà répondu à la seule question qui compte, « est-ce
  /// bien vous ». Les lui poser à nouveau sous deux autres formes ferait
  /// abandonner la connexion au milieu, et c'est ce qui arrivait.
  void _poursuivreSeul() {
    final v = widget.verification;
    if (!_franchies.add(v.state)) return;
    switch (v.state) {
      case KeyVerificationState.askChoice:
        unawaited(v.continueVerification(matrix.EventTypes.Sas));
      case KeyVerificationState.askSas:
        unawaited(v.acceptSas());
      default:
        break;
    }
  }

  Future<void> _faire(Future<void> Function() action) async {
    setState(() => _occupe = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('Vérification interrompue : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  /// Comment nommer l'appareil qui demande.
  ///
  /// Son nom d'affichage s'il en a un, sinon une phrase neutre : un
  /// identifiant de session ne dit rien à personne et ne s'affiche pas.
  String _appareilDemandeur(BuildContext context) {
    final nom = MatrixService.instance
        .clesAppareil(widget.verification.deviceId ?? '')
        ?.deviceDisplayName;
    return nom == null || nom.isEmpty
        ? 'Un appareil demande à ouvrir une session sur votre compte.'
        : '« $nom » demande à ouvrir une session sur votre compte.';
  }

  void _fermer() {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.verification;

    switch (v.state) {
      case KeyVerificationState.askAccept:
        return _cadre(
          titre: 'Confirmer la connexion ?',
          corps: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_appareilDemandeur(context)),
              const SizedBox(height: 12),
              const Text(
                'En acceptant, cet appareil pourra lire vos messages '
                "chiffrés, y compris les anciens. Si ce n'est pas vous, "
                'refusez.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: _occupe
                  ? null
                  : () => _faire(v.rejectVerification).then((_) => _fermer()),
              child: const Text('Refuser'),
            ),
            FilledButton(
              onPressed: _occupe ? null : () => _faire(v.acceptVerification),
              child: const Text('Accepter'),
            ),
          ],
        );

      // Ni le choix de la méthode ni la comparaison des symboles ne sont
      // posés : `_poursuivreSeul` y a déjà répondu, on montre seulement que
      // l'échange avance.
      case KeyVerificationState.askSas:
      case KeyVerificationState.askChoice:
        return _cadre(
          titre: 'Connexion en cours',
          corps: const Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 16),
              Flexible(child: Text('Transmission des clés...')),
            ],
          ),
          actions: [
            TextButton(
              onPressed: _occupe
                  ? null
                  : () => _faire(v.cancel).then((_) => _fermer()),
              child: const Text('Annuler'),
            ),
          ],
        );

      case KeyVerificationState.showQRSuccess:
        return _cadre(
          titre: 'Code reconnu',
          icone: Icons.verified_user,
          corps: const Text(
            "Confirmez sur l'autre appareil pour terminer.",
          ),
          actions: [
            FilledButton(onPressed: _fermer, child: const Text('Fermer')),
          ],
        );

      case KeyVerificationState.confirmQRScan:
        return _cadre(
          titre: 'Code scanné',
          corps: const Text(
            "L'autre appareil dit avoir lu le code. Confirmez seulement s'il "
            "affiche bien qu'il l'a reconnu : c'est ce constat, et lui seul, "
            'qui établit la confiance.',
          ),
          actions: [
            TextButton(
              onPressed: _occupe
                  ? null
                  : () => _faire(v.cancel).then((_) => _fermer()),
              child: const Text('Non'),
            ),
            FilledButton(
              onPressed:
                  _occupe ? null : () => _faire(v.acceptQRScanConfirmation),
              child: const Text('Oui, confirmer'),
            ),
          ],
        );

      case KeyVerificationState.done:
        return _cadre(
          titre: 'Connexion confirmée',
          icone: Icons.verified_user,
          corps: const Text(
            'Cet appareil est désormais reconnu comme le vôtre, et le '
            "restera. Il récupère les clés de l'historique : les messages "
            "jusque-là illisibles s'affichent en quelques secondes.",
          ),
          actions: [
            FilledButton(onPressed: _fermer, child: const Text('Terminer')),
          ],
        );

      case KeyVerificationState.error:
        return _cadre(
          titre: 'Vérification échouée',
          icone: Icons.error_outline,
          corps: Text(
            v.canceledReason?.isNotEmpty ?? false
                ? v.canceledReason!
                : "L'échange a été interrompu. Vous pouvez recommencer.",
          ),
          actions: [
            FilledButton(onPressed: _fermer, child: const Text('Fermer')),
          ],
        );

      // askSSSS, waitingAccept, waitingSas : rien à décider ici, on attend
      // l'autre appareil.
      default:
        return _cadre(
          titre: widget.nousAvonsDemande
              ? "En attente de l'autre appareil"
              : 'Vérification en cours',
          corps: const Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text("Acceptez la demande sur l'autre appareil."),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: _occupe
                  ? null
                  : () => _faire(v.cancel).then((_) => _fermer()),
              child: const Text('Annuler'),
            ),
          ],
        );
    }
  }

  Widget _cadre({
    required String titre,
    required Widget corps,
    required List<Widget> actions,
    IconData? icone,
  }) {
    return AlertDialog(
      icon: icone == null ? null : Icon(icone),
      title: Text(titre),
      content: SingleChildScrollView(child: corps),
      actions: actions,
    );
  }
}

/// Écoute les demandes de vérification venues des autres appareils.
///
/// Enveloppe l'application : une demande arrive quand l'autre appareil la
/// lance, pas quand on ouvre l'écran des appareils. Sans cette écoute, la
/// vérification ne pourrait partir que d'ici, et jamais aboutir.
class EcouteVerifications extends StatefulWidget {
  const EcouteVerifications({
    required this.demandes,
    required this.enfant,
    super.key,
  });

  final Stream<KeyVerification> demandes;
  final Widget enfant;

  @override
  State<EcouteVerifications> createState() => _EcouteVerificationsState();
}

class _EcouteVerificationsState extends State<EcouteVerifications> {
  StreamSubscription<KeyVerification>? _abonnement;
  bool _ouvert = false;

  @override
  void initState() {
    super.initState();
    _abonnement = widget.demandes.listen(_surDemande);
  }

  @override
  void dispose() {
    unawaited(_abonnement?.cancel());
    super.dispose();
  }

  Future<void> _surDemande(KeyVerification verification) async {
    // Une seule vérification à la fois : deux dialogues empilés donneraient
    // deux suites d'emojis différentes, et l'utilisateur comparerait la
    // mauvaise.
    if (_ouvert || !mounted) return;
    _ouvert = true;
    try {
      await ouvrirVerification(verification, nousAvonsDemande: false);
    } finally {
      _ouvert = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.enfant;
}

/// Libellé de l'état de confiance d'un appareil.
///
/// `null` tant que les clés ne sont pas chargées : dire « non vérifié » à ce
/// moment-là serait faux, et inquiéterait pour rien.
({String texte, bool sur})? etatConfiance(matrix.DeviceKeys? cles) {
  if (cles == null) return null;
  if (cles.blocked) return (texte: 'Bloqué', sur: false);
  return cles.verified
      ? (texte: 'Vérifié', sur: true)
      : (texte: 'Non vérifié', sur: false);
}
