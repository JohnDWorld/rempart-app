package com.sovereign.rempart_app

import android.app.DownloadManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.FileProvider
import java.io.File
import java.security.MessageDigest

/**
 * Telechargement d'une mise a jour, confie au systeme.
 *
 * Le telechargement vivait dans l'application : verrouiller l'ecran ou
 * quitter Rempart tuait le processus, et 87 Mo repartaient de zero. Sur
 * plusieurs versions de retard, c'etait intenable.
 *
 * DownloadManager est le service d'Android pour cela : il continue
 * application fermee, reprend apres une coupure reseau, affiche sa propre
 * progression et respecte les reglages d'economie de donnees. Ecrire un
 * service de premier plan a la main aurait fait beaucoup plus de code pour
 * moins de robustesse.
 *
 * A la fin, [MajTelecharge] verifie l'empreinte puis pose une notification :
 * l'installation reste un geste volontaire, et rien ne s'installe en silence.
 */
object Maj {
    const val PREFS = "rempart_maj"
    const val CLE_ID = "download_id"
    const val CLE_EMPREINTE = "sha256"
    const val CLE_FICHIER = "fichier"
    const val DOSSIER = "maj"

    /** Prefixe du drapeau « cet APK a passe la verification d'empreinte ». */
    private const val CLE_PRET = "pret_"

    private const val CANAL = "maj"
    private const val NOTIF_ID = 4201

    /**
     * Met en file le telechargement et rend l'identifiant DownloadManager.
     *
     * Rend -1 si l'APK attendu est deja la, verifie : inutile de retelecharger
     * 87 Mo parce que la notification precedente a ete balayee. L'installateur
     * est alors propose tout de suite.
     */
    fun telecharger(
        context: Context,
        url: String,
        empreinte: String,
        versionCode: Int,
        versionNom: String,
    ): Long {
        val fichier = File(context.getExternalFilesDir(DOSSIER), "rempart-$versionCode.apk")

        if (fichier.exists() && empreinteValide(fichier, empreinte)) {
            notifierPret(context, fichier)
            return -1L
        }
        // Un telechargement interrompu laisse un fichier tronque, que la
        // verification rejetterait ensuite sans que l'on comprenne pourquoi.
        fichier.delete()

        val requete = DownloadManager.Request(Uri.parse(url))
            .setTitle("Mise à jour de Rempart")
            .setDescription("Version $versionNom")
            .setMimeType("application/vnd.android.package-archive")
            // La progression s'affiche pendant le telechargement puis
            // disparait : c'est notre propre notification, posee seulement
            // apres verification de l'empreinte, qui invite a installer.
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
            .setDestinationInExternalFilesDir(context, DOSSIER, fichier.name)
            // L'utilisateur vient de demander la mise a jour : lui refuser les
            // donnees mobiles le laisserait attendre un wifi sans explication.
            .setAllowedOverMetered(true)
            .setAllowedOverRoaming(false)

        val gestionnaire =
            context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val id = gestionnaire.enqueue(requete)

        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putLong(CLE_ID, id)
            .putString(CLE_EMPREINTE, empreinte)
            .putString(CLE_FICHIER, fichier.absolutePath)
            .apply()
        return id
    }

    /**
     * Ou en est le telechargement en cours ? Null s'il n'y en a pas.
     *
     * On interroge DownloadManager plutot que de tenir un drapeau : lui seul
     * sait, et il continue application fermee. Un drapeau pose ici serait faux
     * des le premier redemarrage, et l'ecran afficherait « Telecharger » sur un
     * transfert deja en route, invitant a le lancer une seconde fois.
     */
    fun progression(context: Context): Map<String, Any>? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val id = prefs.getLong(CLE_ID, -1L)
        if (id < 0) return null

        val gestionnaire =
            context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val curseur = gestionnaire.query(DownloadManager.Query().setFilterById(id))
            ?: return null
        curseur.use {
            if (!it.moveToFirst()) return null
            val statut = it.getInt(it.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
            if (statut != DownloadManager.STATUS_RUNNING &&
                statut != DownloadManager.STATUS_PENDING &&
                statut != DownloadManager.STATUS_PAUSED
            ) {
                return null
            }
            val fait = it.getLong(
                it.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR),
            )
            val total = it.getLong(
                it.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES),
            )
            return mapOf(
                "octets" to fait,
                // -1 tant que le serveur n'a pas annonce la taille : l'appelant
                // affiche alors « Telechargement... » sans pourcentage, plutot
                // qu'un chiffre faux.
                "total" to total,
                // En pause vaut « en cours » pour l'utilisateur : le systeme
                // reprendra seul, et il n'a rien a faire de plus.
                "enPause" to (statut == DownloadManager.STATUS_PAUSED),
            )
        }
    }

    /** Verifie le fichier telecharge, puis invite a installer. */
    fun terminer(context: Context, fichier: File, empreinte: String) {
        if (!fichier.exists()) return
        if (!empreinteValide(fichier, empreinte)) {
            // Envoi coupe, disque plein, fichier substitue : Android refuserait
            // l'APK avec un message incomprehensible. Mieux vaut le dire.
            fichier.delete()
            notifier(
                context,
                "Mise à jour non installée",
                "Le fichier téléchargé est incomplet. Réessayez.",
                null,
            )
            return
        }
        notifierPret(context, fichier)
    }

    /**
     * L'APK de cette version attend-il, deja verifie ? Rend son chemin, ou null.
     *
     * On lit un drapeau pose apres la verification plutot que de rehacher :
     * 104 Mo prennent plusieurs secondes, et cette question est posee pour
     * afficher un bouton, donc a chaque ouverture de l'ecran.
     */
    fun apkPret(context: Context, versionCode: Int): String? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean("$CLE_PRET$versionCode", false)) return null
        val fichier = File(context.getExternalFilesDir(DOSSIER), "rempart-$versionCode.apk")
        if (!fichier.exists()) {
            // Efface a la main, ou par le nettoyage du systeme : le drapeau
            // ment, on le retire plutot que de proposer un fichier absent.
            prefs.edit().remove("$CLE_PRET$versionCode").apply()
            return null
        }
        return fichier.absolutePath
    }

    /**
     * Efface les APK devenus inutiles : ceux dont la version est deja installee.
     *
     * Rien ne les supprimait, et chacun pese une centaine de mega-octets. Le
     * moment ou l'on sait qu'un APK ne sert plus est celui-ci : l'application
     * tourne, sa version est connue, tout ce qui lui est anterieur ou egal a
     * fait son office ou ne le fera jamais.
     */
    fun purger(context: Context, versionInstallee: Int) {
        val dossier = context.getExternalFilesDir(DOSSIER) ?: return
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val edition = prefs.edit()
        dossier.listFiles()?.forEach { fichier ->
            val code = Regex("""^rempart-(\d+)\.apk$""")
                .find(fichier.name)?.groupValues?.get(1)?.toIntOrNull()
            if (code == null || code <= versionInstallee) {
                fichier.delete()
                if (code != null) edition.remove("$CLE_PRET$code")
            }
        }
        edition.apply()
    }

    private fun notifierPret(context: Context, fichier: File) {
        // Le drapeau vaut pour l'application : la notification peut etre
        // balayee, ou jamais posee (Android 13 sans autorisation), l'APK
        // verifie reste proposable depuis les parametres.
        val code = Regex("""^rempart-(\d+)\.apk$""")
            .find(fichier.name)?.groupValues?.get(1)?.toIntOrNull()
        if (code != null) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putBoolean("$CLE_PRET$code", true)
                .apply()
        }
        val uri = FileProvider.getUriForFile(
            context, "${context.packageName}.maj", fichier,
        )
        val intention = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            // L'installateur est un autre processus : sans cette permission il
            // recoit un content:// qu'il n'a pas le droit de lire.
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        notifier(
            context,
            "Mise à jour prête",
            "Appuyez pour installer Rempart",
            PendingIntent.getActivity(
                context,
                0,
                intention,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ),
        )
    }

    private fun notifier(
        context: Context,
        titre: String,
        texte: String,
        action: PendingIntent?,
    ) {
        creerCanal(context)
        val notification = NotificationCompat.Builder(context, CANAL)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle(titre)
            .setContentText(texte)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .apply { action?.let { setContentIntent(it) } }
            .build()
        try {
            NotificationManagerCompat.from(context).notify(NOTIF_ID, notification)
        } catch (_: SecurityException) {
            // Android 13+ sans POST_NOTIFICATIONS : rien a faire ici, l'APK
            // verifie reste sur le telephone et sera propose au prochain
            // passage dans l'application.
        }
    }

    private fun creerCanal(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val canal = NotificationChannel(
            CANAL,
            "Mises à jour",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply { description = "Nouvelle version de Rempart prête à installer" }
        val gestionnaire =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        gestionnaire.createNotificationChannel(canal)
    }

    /**
     * Empreinte SHA-256 du fichier, comparee a celle du manifeste.
     *
     * Lue par blocs : charger 87 Mo en memoire d'un coup ferait tomber les
     * telephones les plus justes, ceux-la memes qui mettent le plus longtemps
     * a telecharger.
     */
    private fun empreinteValide(fichier: File, attendue: String): Boolean {
        if (attendue.isBlank()) return true
        return try {
            val digest = MessageDigest.getInstance("SHA-256")
            fichier.inputStream().use { flux ->
                val tampon = ByteArray(64 * 1024)
                while (true) {
                    val lus = flux.read(tampon)
                    if (lus <= 0) break
                    digest.update(tampon, 0, lus)
                }
            }
            digest.digest().joinToString("") { "%02x".format(it) }
                .equals(attendue, ignoreCase = true)
        } catch (_: Exception) {
            false
        }
    }
}

/**
 * Fin de telechargement signalee par DownloadManager.
 *
 * Declare dans le manifeste et non enregistre a l'execution : il doit
 * s'executer meme si Rempart n'est plus lance, ce qui est tout l'interet.
 *
 * Le recepteur est exporte, comme l'exige un broadcast venu du systeme. Il ne
 * fait donc confiance a rien : l'identifiant doit etre celui que nous avons
 * memorise, et l'empreinte doit correspondre.
 */
class MajTelecharge : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != DownloadManager.ACTION_DOWNLOAD_COMPLETE) return
        val id = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L)
        val prefs = context.getSharedPreferences(Maj.PREFS, Context.MODE_PRIVATE)
        if (id == -1L || id != prefs.getLong(Maj.CLE_ID, -1L)) return

        val chemin = prefs.getString(Maj.CLE_FICHIER, null) ?: return
        val empreinte = prefs.getString(Maj.CLE_EMPREINTE, "") ?: ""

        // Hacher 87 Mo depasse les quelques millisecondes accordees a un
        // recepteur : goAsync() tient le systeme informe pendant qu'un fil
        // separe travaille.
        val resultat = goAsync()
        Thread {
            try {
                Maj.terminer(context.applicationContext, File(chemin), empreinte)
            } finally {
                resultat.finish()
            }
        }.start()
    }
}
