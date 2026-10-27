import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    exclureDocumentsDesSauvegardes()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "Rempart") {
      brancherCanaux(registrar.messenger())
    }
  }

  /// Les canaux propres à Rempart, jumeaux de ceux de `MainActivity.kt` :
  /// mêmes noms, mêmes méthodes, mêmes réponses. Le code Dart n'a pas à savoir
  /// sur quel système il tourne, seulement si la fonction y existe.
  private func brancherCanaux(_ messager: FlutterBinaryMessenger) {
    // Aperçu d'un PDF reçu (ApercuPdf), hors du fil principal : une page prend
    // une centaine de millisecondes à rendre.
    FlutterMethodChannel(name: "rempart/pdf", binaryMessenger: messager)
      .setMethodCallHandler { appel, reponse in
        guard ["pages", "page"].contains(appel.method),
              let arguments = appel.arguments as? [String: Any],
              let chemin = arguments["chemin"] as? String
        else {
          reponse(FlutterMethodNotImplemented)
          return
        }
        DispatchQueue.global(qos: .userInitiated).async {
          let resultat = Result<Any, Error>(catching: {
            if appel.method == "pages" { return try ApercuPdf.nombreDePages(chemin) }
            return FlutterStandardTypedData(bytes: try ApercuPdf.page(
              chemin,
              index: arguments["index"] as? Int ?? 0,
              largeur: arguments["largeur"] as? Int ?? 1080
            ))
          })
          DispatchQueue.main.async {
            switch resultat {
            case .success(let valeur): reponse(valeur)
            // PDF protégé ou abîmé : l'aperçu se replie sur la fiche du fichier.
            case .failure(let erreur):
              reponse(FlutterError(code: "pdf", message: erreur.localizedDescription, details: nil))
            }
          }
        }
      }

    // Compression d'une vidéo à l'envoi (CompressionVideo).
    let canalVideo = FlutterMethodChannel(name: "rempart/video", binaryMessenger: messager)
    canalVideo.setMethodCallHandler { appel, reponse in
      guard let arguments = appel.arguments as? [String: Any],
            let entree = arguments["entree"] as? String
      else {
        reponse(FlutterMethodNotImplemented)
        return
      }
      switch appel.method {
      case "mesurer":
        Task {
          do {
            let mesure = try await CompressionVideo.mesurer(entree)
            await MainActor.run { reponse(mesure) }
          } catch {
            await MainActor.run {
              reponse(FlutterError(code: "mesure", message: error.localizedDescription, details: nil))
            }
          }
        }
      case "compresser":
        guard let sortie = arguments["sortie"] as? String,
              let debit = arguments["debit"] as? Int
        else {
          reponse(FlutterError(code: "compression", message: "arguments manquants", details: nil))
          return
        }
        Task {
          do {
            try await CompressionVideo.compresser(
              entree: entree,
              sortie: sortie,
              debit: debit,
              coteCourt: arguments["coteCourt"] as? Int ?? 0
            ) { pourcent in
              canalVideo.invokeMethod("progression", arguments: pourcent)
            }
            await MainActor.run { reponse(nil) }
          } catch {
            await MainActor.run {
              reponse(FlutterError(code: "compression", message: error.localizedDescription, details: nil))
            }
          }
        }
      default:
        reponse(FlutterMethodNotImplemented)
      }
    }

    // Réglages du temps d'un vocal (EnregistreurVocal). iOS n'en a qu'un à
    // faire lui-même : empêcher la veille, qui couperait l'enregistrement. Le
    // reste du canal (mises à jour, batterie, focus audio) est propre à
    // Android, et le code Dart ne l'appelle pas ici.
    FlutterMethodChannel(name: "rempart/maj", binaryMessenger: messager)
      .setMethodCallHandler { appel, reponse in
        switch appel.method {
        case "garderEcranAllume":
          UIApplication.shared.isIdleTimerDisabled = appel.arguments as? Bool ?? false
          reponse(nil)
        default:
          reponse(FlutterMethodNotImplemented)
        }
      }
  }

  /// Rien de ce que Rempart écrit dans Documents ne part dans une sauvegarde
  /// iCloud ou Finder.
  ///
  /// La base locale y vit, et elle contient les messages DÉCHIFFRÉS, les clés
  /// de l'appareil et les secrets du coffre. Sur un nouvel iPhone, on se
  /// reconnecte, et l'historique revient par la sauvegarde CHIFFRÉE des clés
  /// de Matrix, pas par celle du système.
  ///
  /// Le dossier entier et non le seul fichier : SQLite crée et efface son
  /// journal à chaque transaction, et un fichier recréé perdrait la marque.
  /// Posée à chaque lancement, avant que Dart n'ouvre la base : l'opération
  /// ne coûte rien et répare un dossier qui l'aurait perdue.
  private func exclureDocumentsDesSauvegardes() {
    guard var dossier = FileManager.default.urls(
      for: .documentDirectory, in: .userDomainMask
    ).first else { return }
    var valeurs = URLResourceValues()
    valeurs.isExcludedFromBackup = true
    do {
      try dossier.setResourceValues(valeurs)
    } catch {
      NSLog("Rempart : Documents non exclu des sauvegardes (\(error))")
    }
  }
}
