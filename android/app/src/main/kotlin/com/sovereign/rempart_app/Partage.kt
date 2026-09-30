package com.sovereign.rempart_app

import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import androidx.core.content.IntentCompat
import java.io.File

/**
 * Ce qu'une autre application confie a Rempart par « Partager » : photos,
 * videos, fichiers, ou un simple texte (un lien, le plus souvent).
 *
 * Retenu a l'arrivee de l'intention, puis copie dans le cache quand Flutter
 * le demande : les adresses content:// ne se lisent que d'ici, et le droit de
 * les lire expire avec l'activite qui les a recues.
 */
object Partage {

    @Volatile
    private var enAttente: Intent? = null

    /** Retient l'intention si c'est un partage ; rend vrai dans ce cas. */
    fun retenir(intent: Intent?): Boolean {
        if (intent == null) return false
        if (intent.action != Intent.ACTION_SEND && intent.action != Intent.ACTION_SEND_MULTIPLE) {
            return false
        }
        // Rouverte depuis les applications recentes, l'activite recoit a
        // nouveau l'intention qui l'avait lancee : sans ce garde, un partage
        // deja envoye se proposerait une seconde fois.
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return false
        enAttente = intent
        return true
    }

    /**
     * Copie les fichiers du partage en attente dans le cache, et les rend
     * avec leur nom et leur type. Null s'il n'y a rien.
     *
     * Lit des fichiers : a appeler hors du fil principal.
     */
    fun prendre(context: Context): Map<String, Any?>? {
        val intent = enAttente ?: return null
        enAttente = null

        // Le partage precedent a fini son office : un seul a la fois.
        val dossier = File(context.cacheDir, "partage").apply {
            deleteRecursively()
            mkdirs()
        }
        val adresses = if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            IntentCompat.getParcelableArrayListExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)
                ?: emptyList()
        } else {
            listOfNotNull(
                IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java),
            )
        }

        val fichiers = adresses.mapIndexedNotNull { i, uri ->
            // Un fichier illisible (droit retire, source effacee) ne doit pas
            // emporter les autres avec lui.
            try {
                copier(context, uri, File(dossier, "$i"), intent.type)
            } catch (e: Exception) {
                null
            }
        }
        val texte = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
        if (fichiers.isEmpty() && texte.isNullOrBlank()) return null
        return mapOf("fichiers" to fichiers, "texte" to texte)
    }

    private fun copier(context: Context, uri: Uri, dossier: File, typeIntention: String?): Map<String, Any?>? {
        if (!lisible(context, uri)) return null
        val nom = nomDe(context.contentResolver, uri)
        // Le nom vient d'une autre application : `File(...).name` en retire
        // tout chemin (« ../ »), et un dossier par fichier evite qu'un doublon
        // n'ecrase son voisin.
        dossier.mkdirs()
        val nomSur = File(nom).name.takeUnless { it.isBlank() || it == "." || it == ".." }
            ?: "fichier"
        val copie = File(dossier, nomSur)
        context.contentResolver.openInputStream(uri)?.use { entree ->
            copie.outputStream().use { entree.copyTo(it) }
        } ?: return null
        return mapOf(
            "chemin" to copie.absolutePath,
            "nom" to nom,
            "type" to (context.contentResolver.getType(uri) ?: typeIntention),
        )
    }

    /**
     * Seules les adresses content:// d'une AUTRE application sont lues.
     *
     * Une application malveillante peut « partager » file:///data/data/...
     * ou une adresse d'un fournisseur de Rempart lui-meme : Rempart lirait
     * alors ses propres fichiers (base de messages, cles, medias dechiffres)
     * pour les poser dans une conversation.
     */
    private fun lisible(context: Context, uri: Uri): Boolean {
        if (uri.scheme != ContentResolver.SCHEME_CONTENT) return false
        val autorite = uri.authority ?: return false
        val fournisseur = context.packageManager.resolveContentProvider(autorite, 0)
        return fournisseur?.packageName != context.packageName
    }

    private fun nomDe(resolver: ContentResolver, uri: Uri): String {
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) {
                val nom = it.getString(0)
                if (!nom.isNullOrBlank()) return nom
            }
        }
        return uri.lastPathSegment?.let { File(it).name }?.takeIf { it.isNotBlank() } ?: "fichier"
    }
}
