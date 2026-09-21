import java.util.Properties

// Signature de release. Le fichier reste hors du depot (sa version chiffree
// est committee, voir `make keystore-decrypt`) ; absent, le build retombe sur
// la cle de debug pour qu'un clone frais compile quand meme.
val cleRelease = Properties().apply {
    val fichier = rootProject.file("key.properties")
    if (fichier.exists()) fichier.inputStream().use { load(it) }
}
val signatureDisponible = cleRelease.getProperty("storeFile")?.let {
    rootProject.file(it).exists()
} ?: false

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.sovereign.rempart_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        // Identifiant definitif, tire du domaine rempart-messenger.fr (le tiret
        // n'est pas permis ici, d'ou le tiret bas). Il ne changera plus : le
        // Play Store le grave au premier envoi.
        //
        // Le `namespace` Kotlin garde son ancien nom : il ne sert qu'au code
        // genere et ne se voit nulle part, alors que le renommer deplacerait
        // les sources pour rien.
        applicationId = "fr.rempart_messenger.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (signatureDisponible) {
            create("release") {
                storeFile = rootProject.file(cleRelease.getProperty("storeFile"))
                storePassword = cleRelease.getProperty("storePassword")
                keyAlias = cleRelease.getProperty("keyAlias")
                keyPassword = cleRelease.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Sans la cle de release, on signe en debug : l'APK s'installe
            // pour un essai local, mais il ne peut pas remplacer une version
            // signee avec la vraie cle (Android refuse un changement de
            // signature). Les APK distribues doivent donc sortir d'une machine
            // qui a key.properties.
            signingConfig = signingConfigs.getByName(
                if (signatureDisponible) "release" else "debug",
            )
        }
    }
}

flutter {
    source = "../.."
}

// Tink arrive en double : la variante JVM (com.google.crypto.tink:tink, tiree
// par unifiedpush) et la variante Android (tink-android, tiree par le stockage
// securise) declarent les memes classes, ce qui fait echouer le build sur
// checkDebugDuplicateClasses. On garde la variante Android, seule adaptee ici.
configurations.all {
    exclude(group = "com.google.crypto.tink", module = "tink")
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    // FileProvider, utilise par MainActivity pour passer l'APK telecharge a
    // l'installateur. Des greffons l'amenent deja de facon transitive ; la
    // declarer ici evite que le pont casse si l'un d'eux disparait.
    implementation("androidx.core:core-ktx:1.13.1")
}
