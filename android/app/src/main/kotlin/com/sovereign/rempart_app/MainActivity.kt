package com.sovereign.rempart_app

import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.view.View
import android.view.WindowManager
import android.view.WindowInsets
import android.view.WindowInsetsAnimation
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Pont vers l'installateur d'Android pour les mises a jour hors magasin.
 *
 * Aucun greffon ne fait cela ; c'est une intention et un fournisseur de
 * fichiers, soit moins de code ici qu'une dependance de plus a suivre.
 */
class MainActivity : FlutterActivity() {

    private val canal = "rempart/maj"

    /** Previent Flutter qu'un partage vient d'arriver, application ouverte. */
    private var canalPartage: MethodChannel? = null

    /**
     * Le focus audio pris le temps d'un vocal (voir "focusAudio"). L'ecouteur
     * ne fait rien : la pause au depart de l'ecran couvre deja un appel.
     */
    private var demandeFocus: AudioFocusRequest? = null
    private val ecouteFocus = AudioManager.OnAudioFocusChangeListener { }

    /**
     * Clavier fantome : au retour dans l'application, un espace vide de la
     * hauteur du clavier restait en bas de TOUS les ecrans, clavier ferme.
     *
     * Le moteur retient les marges du clavier pendant son animation et ne les
     * transmet qu'a la fin (`ImeSyncDeferringInsetsCallback`) : a `onEnd`, il
     * renvoie les DERNIERES marges qu'il a mises de cote. Vecu le 2026-09-27
     * sur le Xiaomi : Rempart quitte par le geste, clavier ouvert, mis en
     * veille par MIUI, puis rouvert par son icone. MIUI anime alors la
     * fermeture du clavier, deux fois de suite, pendant la transition
     * d'ouverture (journal : deux `hide: ime`, puis `ImeTracker onTimeout at
     * PHASE_CLIENT_REPORT_REQUESTED_VISIBLE_TYPES`). Les vraies marges ne
     * tombent pas dans la fenetre que le moteur surveille, et il ressert
     * celles d'avant le depart, clavier ouvert. Code identique dans le Flutter
     * le plus recent (sept. 2026) : rien a attendre d'une mise a jour.
     *
     * Remede : apres chaque animation du clavier, et au retour de la fenetre
     * (au cas ou l'animation ne finirait jamais), si Android dit le clavier
     * ferme, donner a la vue Flutter les vraies marges en passant a cote de
     * l'intercepteur, comme le moteur le fait lui-meme pendant ses animations.
     * Sans effet quand tout va bien : les marges sont deja celles-la.
     */
    override fun onCreate(savedInstanceState: Bundle?) {
        // Lancee par « Partager » depuis une autre application : Flutter
        // viendra le chercher une fois demarre.
        Partage.retenir(intent)
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        val vue = findViewById<View>(FlutterActivity.FLUTTER_VIEW_ID) ?: return
        // Pose sur le PARENT : la vue Flutter a deja le sien, qu'un second
        // remplacerait. CONTINUE_ON_SUBTREE le laisse recevoir l'animation.
        (vue.parent as? View)?.setWindowInsetsAnimationCallback(
            object : WindowInsetsAnimation.Callback(DISPATCH_MODE_CONTINUE_ON_SUBTREE) {
                override fun onProgress(
                    insets: WindowInsets,
                    animations: MutableList<WindowInsetsAnimation>,
                ) = insets

                override fun onEnd(animation: WindowInsetsAnimation) {
                    // Le parent recoit onEnd AVANT l'enfant : attendre que le
                    // moteur ait fini de renvoyer ses marges.
                    if (animation.typeMask and WindowInsets.Type.ime() != 0) {
                        vue.post { realignerClavier(vue) }
                    }
                }
            },
        )
    }

    /**
     * Partage recu application ouverte. `singleTask` (voir le manifeste) le
     * fait arriver ici, dans l'activite existante, au lieu d'ouvrir une
     * seconde copie de Rempart dans la tache de l'application qui partage :
     * deux moteurs Flutter, donc deux clients Matrix sur la meme base.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (Partage.retenir(intent)) canalPartage?.invokeMethod("nouveau", null)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus || Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        val vue = findViewById<View>(FlutterActivity.FLUTTER_VIEW_ID) ?: return
        // ponytail: delai fixe, le temps qu'une fermeture lancee au retour ait
        // fini (une demi-seconde mesuree) ; ne sert que si onEnd n'arrive pas.
        vue.postDelayed({ realignerClavier(vue) }, 1000)
    }

    private fun realignerClavier(vue: View) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        val marges = vue.rootWindowInsets ?: return
        if (!marges.isVisible(WindowInsets.Type.ime())) vue.onApplyWindowInsets(marges)
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        canalPartage = MethodChannel(engine.dartExecutor.binaryMessenger, "rempart/partage").apply {
            setMethodCallHandler { appel, reponse ->
                if (appel.method != "prendre") {
                    reponse.notImplemented()
                    return@setMethodCallHandler
                }
                // Copie de fichiers, parfois lourds (une video) : hors du fil
                // principal, qui gelerait l'ecran le temps de la copie.
                Thread {
                    val partage = try {
                        Partage.prendre(applicationContext)
                    } catch (e: Exception) {
                        null
                    }
                    runOnUiThread { reponse.success(partage) }
                }.start()
            }
        }
        // Apercu d'un PDF recu (ApercuPdf) : hors du fil principal, une page
        // prend une centaine de millisecondes a rendre.
        MethodChannel(engine.dartExecutor.binaryMessenger, "rempart/pdf").setMethodCallHandler {
            appel, reponse ->
            val chemin = appel.argument<String>("chemin")
            if (appel.method !in setOf("pages", "page") || chemin == null) {
                reponse.notImplemented()
                return@setMethodCallHandler
            }
            Thread {
                val resultat = runCatching {
                    if (appel.method == "pages") {
                        ApercuPdf.nombreDePages(chemin)
                    } else {
                        ApercuPdf.page(
                            chemin,
                            appel.argument<Int>("index") ?: 0,
                            appel.argument<Int>("largeur") ?: 1080,
                        )
                    }
                }
                runOnUiThread {
                    resultat.fold(
                        { reponse.success(it) },
                        // PDF protege par mot de passe ou abime : PdfRenderer
                        // leve, et l'apercu se replie sur la fiche du fichier.
                        { reponse.error("pdf", it.message, null) },
                    )
                }
            }.start()
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, canal).setMethodCallHandler {
            appel, reponse ->
            when (appel.method) {
                // Android 8+ : l'autorisation « installer des applications
                // inconnues » se donne par application. Sans elle, l'intention
                // s'ouvre sur un ecran vide et l'utilisateur ne comprend pas.
                // (avant Android 8, l'autorisation etait globale au telephone)
                "peutInstaller" -> reponse.success(
                    Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                        packageManager.canRequestPackageInstalls(),
                )

                "ouvrirReglageInstallation" -> {
                    startActivity(
                        Intent(
                            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:$packageName"),
                        ),
                    )
                    reponse.success(null)
                }

                // Telechargement confie au systeme : il survit a la
                // fermeture de l'application et au verrouillage de l'ecran.
                "telechargerEnFond" -> {
                    val url = appel.argument<String>("url")
                    val version = appel.argument<Int>("versionCode")
                    if (url == null || version == null) {
                        reponse.error("arguments", "url et versionCode requis", null)
                        return@setMethodCallHandler
                    }
                    try {
                        reponse.success(
                            Maj.telecharger(
                                applicationContext,
                                url,
                                appel.argument<String>("sha256") ?: "",
                                version,
                                appel.argument<String>("versionNom") ?: "",
                            ),
                        )
                    } catch (e: Exception) {
                        reponse.error("telechargement", e.message, null)
                    }
                }

                // L'APK de cette version attend-il deja, verifie ? C'est ce
                // qui fait dire « Installer » au bouton plutot que
                // « Telecharger », et qui rend la notification facultative.
                "apkPret" -> {
                    val version = appel.argument<Int>("versionCode")
                    if (version == null) {
                        reponse.error("arguments", "versionCode requis", null)
                        return@setMethodCallHandler
                    }
                    reponse.success(Maj.apkPret(applicationContext, version))
                }

                // Ou en est le telechargement ? Rend null s'il n'y en a pas.
                "progressionMaj" -> reponse.success(Maj.progression(applicationContext))

                "purger" -> {
                    val version = appel.argument<Int>("versionInstallee")
                    if (version == null) {
                        reponse.error("arguments", "versionInstallee requise", null)
                        return@setMethodCallHandler
                    }
                    Maj.purger(applicationContext, version)
                    reponse.success(null)
                }

                // Android endort les applications qu'il juge inutilisees, et
                // Samsung plus tot que les autres : un message pousse
                // n'arrive alors qu'au reveil, c'est-a-dire quand on ouvre
                // Rempart, ce qui vide la notification de son interet.
                "batterieBridee" -> {
                    val power = getSystemService(Context.POWER_SERVICE) as PowerManager
                    reponse.success(!power.isIgnoringBatteryOptimizations(packageName))
                }

                // La LISTE des reglages, et non la demande directe : celle-ci
                // exige REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, une permission
                // que le Play Store n'accorde qu'au cas par cas. Un ecran de
                // plus a traverser vaut mieux qu'une publication refusee.
                // Pendant un vocal : un ecran eteint fait quitter l'ecran a
                // Rempart, et Android ne donne plus alors que du silence au
                // micro. Le drapeau ne vaut que pour cette fenetre, et se
                // retire a la fin de l'enregistrement.
                "garderEcranAllume" -> {
                    if (appel.arguments == true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    reponse.success(null)
                }

                // Pendant un vocal : la musique des autres applications
                // (Spotify, la radio de la voiture) se met en pause, et reprend
                // seule a la fin. Transitoire et exclusif : un lecteur s'arrete
                // au lieu de baisser le son, et reprend quand on rend la main.
                // Le focus DEFINITIF que prenait le greffon d'enregistrement
                // arretait Spotify pour de bon : il fallait relancer la musique
                // a la main apres chaque vocal.
                "focusAudio" -> {
                    val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    if (appel.arguments == true) {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val demande = AudioFocusRequest.Builder(
                                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE,
                            )
                                .setAudioAttributes(
                                    AudioAttributes.Builder()
                                        .setUsage(AudioAttributes.USAGE_MEDIA)
                                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                                        .build(),
                                )
                                .setOnAudioFocusChangeListener(ecouteFocus)
                                .build()
                            demandeFocus = demande
                            audio.requestAudioFocus(demande)
                        } else {
                            @Suppress("DEPRECATION")
                            audio.requestAudioFocus(
                                ecouteFocus,
                                AudioManager.STREAM_MUSIC,
                                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE,
                            )
                        }
                    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        demandeFocus?.let { audio.abandonAudioFocusRequest(it) }
                        demandeFocus = null
                    } else {
                        @Suppress("DEPRECATION")
                        audio.abandonAudioFocus(ecouteFocus)
                    }
                    reponse.success(null)
                }

                "ouvrirReglageBatterie" -> {
                    startActivity(
                        Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
                    )
                    reponse.success(null)
                }

                "installer" -> {
                    val chemin = appel.argument<String>("chemin")
                    if (chemin == null) {
                        reponse.error("chemin", "chemin de l'APK manquant", null)
                        return@setMethodCallHandler
                    }
                    val fichier = File(chemin)
                    if (!fichier.exists()) {
                        reponse.error("absent", "APK introuvable : $chemin", null)
                        return@setMethodCallHandler
                    }
                    val uri = FileProvider.getUriForFile(
                        this, "$packageName.maj", fichier,
                    )
                    startActivity(
                        Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            // L'installateur est un autre processus : sans cette
                            // permission il recoit un content:// qu'il n'a pas le
                            // droit de lire, et echoue sans rien dire d'utile.
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        },
                    )
                    reponse.success(null)
                }

                else -> reponse.notImplemented()
            }
        }
    }
}
