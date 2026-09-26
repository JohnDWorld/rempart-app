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
