import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Scanne le QR affiché par l'autre appareil et rend ses octets bruts.
///
/// Pour un code d'appairage (du texte JSON), voir [scannerTexteQr].
///
/// Rend `null` si l'utilisateur renonce.
///
/// Les **octets bruts** et non le texte : le QR de vérification Matrix
/// transporte du binaire (clés publiques et secret partagé), que la lecture
/// en texte abîmerait sans rien signaler, tout octet hors ASCII étant
/// réinterprété. `rawBytes` est le seul chemin correct.
Future<Uint8List?> scannerQrVerification(BuildContext context) {
  return Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(builder: (context) => const _EcranScan()),
  );
}

class _EcranScan extends StatefulWidget {
  const _EcranScan();

  @override
  State<_EcranScan> createState() => _EcranScanState();
}

class _EcranScanState extends State<_EcranScan> {
  final _controleur = MobileScannerController(
    // Un seul code nous intéresse, et la caméra n'a pas à rester allumée
    // une fois qu'on l'a.
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _rendu = false;

  @override
  void dispose() {
    unawaited(_controleur.dispose());
    super.dispose();
  }

  void _surDetection(BarcodeCapture capture) {
    if (_rendu) return;
    for (final code in capture.barcodes) {
      // Le type diffère selon la plateforme : Android et le web rendent les
      // octets décodés, Apple y ajoute la charge brute avec en-tête.
      final octets = switch (code.rawDecodedBytes) {
        DecodedBarcodeBytes(:final bytes) => bytes,
        DecodedVisionBarcodeBytes(:final bytes) => bytes,
        _ => null,
      };
      if (octets == null || octets.isEmpty) continue;
      _rendu = true;
      Navigator.of(context).pop(octets);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scanner le code')),
      body: Stack(
        children: [
          MobileScanner(controller: _controleur, onDetect: _surDetection),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              color: Colors.black54,
              padding: const EdgeInsets.all(20),
              child: const Text(
                "Visez le code affiché sur l'autre appareil.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


/// Scanne un QR **textuel**, celui de l'appairage.
///
/// Rend `null` si l'utilisateur renonce. Séparé du scan binaire de la
/// vérification : là ce sont des clés, ici du JSON, et les confondre donnerait
/// des erreurs incompréhensibles.
Future<String?> scannerTexteQr(
  BuildContext context, {
  required String titre,
  required String consigne,
  bool Function(String)? accepter,
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (context) => _EcranScanTexte(
        titre: titre,
        consigne: consigne,
        accepter: accepter,
      ),
    ),
  );
}

class _EcranScanTexte extends StatefulWidget {
  const _EcranScanTexte({
    required this.titre,
    required this.consigne,
    this.accepter,
  });

  final String titre;
  final String consigne;
  final bool Function(String)? accepter;

  @override
  State<_EcranScanTexte> createState() => _EcranScanTexteState();
}

class _EcranScanTexteState extends State<_EcranScanTexte> {
  final _controleur = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _rendu = false;

  @override
  void dispose() {
    unawaited(_controleur.dispose());
    super.dispose();
  }

  void _surDetection(BarcodeCapture capture) {
    if (_rendu) return;
    for (final code in capture.barcodes) {
      final texte = code.displayValue ?? code.rawValue;
      if (texte == null || texte.isEmpty) continue;
      // Un QR du monde extérieur (une affiche, un menu) ne doit pas remonter :
      // l'appelant dirait alors une erreur qui n'apprendrait rien.
      if (widget.accepter != null && !widget.accepter!(texte)) continue;
      _rendu = true;
      Navigator.of(context).pop(texte);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.titre)),
      body: Stack(
        children: [
          MobileScanner(controller: _controleur, onDetect: _surDetection),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              color: Colors.black54,
              padding: const EdgeInsets.all(20),
              child: Text(
                widget.consigne,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
