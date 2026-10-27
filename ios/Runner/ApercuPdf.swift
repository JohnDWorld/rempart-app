import PDFKit
import UIKit

/// Aperçu d'un PDF reçu, par PDFKit : l'équivalent iOS de `ApercuPdf.kt`.
///
/// Même contrat que sur Android (canal `rempart/pdf`) : le nombre de pages,
/// puis chaque page en PNG à la largeur demandée. Aucune bibliothèque de plus,
/// et le fichier déchiffré ne quitte pas Rempart.
///
/// Chaque appel rouvre le document : les pages se rendent une à une, au fil du
/// défilement, et rien ne reste ouvert si l'écran se ferme entre deux.
enum ApercuPdf {
  enum Erreur: LocalizedError {
    case illisible
    case protege
    case pageAbsente(Int)

    var errorDescription: String? {
      switch self {
      case .illisible: return "PDF illisible"
      case .protege: return "PDF protégé par un mot de passe"
      case .pageAbsente(let index): return "page \(index) absente"
      }
    }
  }

  static func nombreDePages(_ chemin: String) throws -> Int {
    try ouvrir(chemin).pageCount
  }

  /// La page [index] (à partir de 0), large de [largeur] pixels, en PNG.
  static func page(_ chemin: String, index: Int, largeur: Int) throws -> Data {
    guard let page = try ouvrir(chemin).page(at: index) else {
      throw Erreur.pageAbsente(index)
    }
    // La taille telle qu'on la lit, rotation de la page comprise : une page
    // posée en paysage dans un document en portrait s'affiche couchée sinon.
    var cadre = page.bounds(for: .mediaBox).size
    if page.rotation % 180 != 0 {
      cadre = CGSize(width: cadre.height, height: cadre.width)
    }
    guard cadre.width > 0, cadre.height > 0 else { throw Erreur.illisible }
    let taille = CGSize(
      width: CGFloat(max(1, largeur)),
      height: max(1, (CGFloat(largeur) * cadre.height / cadre.width).rounded())
    )
    let vignette = page.thumbnail(of: taille, for: .mediaBox)

    // Une page PDF n'a pas de fond : sans ce blanc, le texte noir se perdait
    // sur le fond sombre de l'aperçu (même piège que sur Android).
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let image = UIGraphicsImageRenderer(size: taille, format: format).image { contexte in
      UIColor.white.setFill()
      contexte.fill(CGRect(origin: .zero, size: taille))
      vignette.draw(in: CGRect(origin: .zero, size: taille))
    }
    guard let png = image.pngData() else { throw Erreur.illisible }
    return png
  }

  private static func ouvrir(_ chemin: String) throws -> PDFDocument {
    guard let document = PDFDocument(url: URL(fileURLWithPath: chemin)) else {
      throw Erreur.illisible
    }
    // Un PDF chiffré s'ouvre, mais verrouillé : comme sur Android, l'aperçu
    // se replie alors sur la fiche du fichier.
    if document.isLocked { throw Erreur.protege }
    return document
  }
}
