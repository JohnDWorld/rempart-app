package com.sovereign.rempart_app

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import java.io.ByteArrayOutputStream
import java.io.File

/**
 * Apercu d'un PDF recu, par le moteur PDF d'Android (PdfRenderer) : aucune
 * bibliotheque de plus, et le fichier dechiffre ne quitte pas Rempart.
 *
 * Chaque appel rouvre le document : les pages se rendent une a une, au fil
 * du defilement, et rien ne reste ouvert si l'ecran se ferme entre deux.
 * Deux appels simultanes ont chacun leur moteur, celui-ci n'ouvrant qu'une
 * page a la fois.
 */
object ApercuPdf {

    private fun <T> ouvrir(chemin: String, action: (PdfRenderer) -> T): T =
        ParcelFileDescriptor.open(File(chemin), ParcelFileDescriptor.MODE_READ_ONLY)
            .use { fichier -> PdfRenderer(fichier).use(action) }

    fun nombreDePages(chemin: String): Int = ouvrir(chemin) { it.pageCount }

    /** La page [index], large de [largeur] pixels, en PNG. */
    fun page(chemin: String, index: Int, largeur: Int): ByteArray = ouvrir(chemin) { pdf ->
        pdf.openPage(index).use { page ->
            val hauteur = (largeur.toLong() * page.height / page.width).toInt().coerceAtLeast(1)
            val image = Bitmap.createBitmap(largeur, hauteur, Bitmap.Config.ARGB_8888)
            // Une page PDF n'a pas de fond : sans ce blanc, le texte noir se
            // perdait sur le fond sombre de l'apercu.
            image.eraseColor(Color.WHITE)
            page.render(image, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            try {
                ByteArrayOutputStream().use { sortie ->
                    image.compress(Bitmap.CompressFormat.PNG, 100, sortie)
                    sortie.toByteArray()
                }
            } finally {
                image.recycle()
            }
        }
    }
}
