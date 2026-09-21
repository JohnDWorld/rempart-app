package com.sovereign.rempart_app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
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

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
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
