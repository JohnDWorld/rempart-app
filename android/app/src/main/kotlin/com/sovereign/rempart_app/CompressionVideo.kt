package com.sovereign.rempart_app

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import java.io.File

/**
 * Allege une video avant l'envoi, comme WhatsApp : H.264 par l'encodeur
 * materiel du telephone, au debit et a la taille decides cote Dart
 * (`compression_video.dart`). Une video de 100 Mo, refusee par le serveur
 * (50 Mo), en pesait une quinzaine (releve le 2026-10-23).
 *
 * Media3 Transformer, la bibliotheque de Google, gere ce qu'un encodage a la
 * main raterait : la rotation d'une video filmee en portrait, et le HDR des
 * telephones recents, ramene en SDR, que tout le monde sait lire.
 */
@OptIn(UnstableApi::class)
object CompressionVideo {

    /** Duree en millisecondes, largeur et hauteur (avant rotation). */
    fun mesurer(chemin: String): Map<String, Long> {
        val mesure = MediaMetadataRetriever()
        try {
            mesure.setDataSource(chemin)
            fun lire(cle: Int) = mesure.extractMetadata(cle)?.toLongOrNull() ?: 0L
            return mapOf(
                "dureeMs" to lire(MediaMetadataRetriever.METADATA_KEY_DURATION),
                "largeur" to lire(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH),
                "hauteur" to lire(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT),
            )
        } finally {
            mesure.release()
        }
    }

    /**
     * Reencode [entree] dans [sortie] (MP4, H.264 + AAC), au [debit] video
     * donne, le petit cote ramene a [coteCourt] pixels si c'est non nul.
     * A appeler depuis le fil principal : Transformer y rend ses resultats.
     */
    fun compresser(
        context: Context,
        entree: String,
        sortie: String,
        debit: Int,
        coteCourt: Int,
        progression: (Int) -> Unit,
        fin: (ExportException?) -> Unit,
    ) {
        val principal = Handler(Looper.getMainLooper())
        val suivi = ProgressHolder()
        lateinit var transformer: Transformer
        val releve = object : Runnable {
            override fun run() {
                if (transformer.getProgress(suivi) == Transformer.PROGRESS_STATE_AVAILABLE) {
                    progression(suivi.progress)
                }
                principal.postDelayed(this, 400)
            }
        }
        transformer = Transformer.Builder(context)
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .setAudioMimeType(MimeTypes.AUDIO_AAC)
            .setEncoderFactory(
                DefaultEncoderFactory.Builder(context)
                    .setRequestedVideoEncoderSettings(
                        VideoEncoderSettings.Builder().setBitrate(debit).build(),
                    )
                    // Un encodeur qui refuse un reglage en propose un voisin
                    // plutot que d'echouer.
                    .setEnableFallback(true)
                    .build(),
            )
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, resultat: ExportResult) {
                    principal.removeCallbacks(releve)
                    fin(null)
                }

                override fun onError(
                    composition: Composition,
                    resultat: ExportResult,
                    erreur: ExportException,
                ) {
                    principal.removeCallbacks(releve)
                    fin(erreur)
                }
            })
            .build()

        val effets = if (coteCourt > 0) listOf(Presentation.createForShortSide(coteCourt)) else emptyList()
        val video = EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(File(entree))))
            .setEffects(Effects(emptyList(), effets))
            .build()
        val composition = Composition.Builder(EditedMediaItemSequence.Builder(video).build())
            .setHdrMode(Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL)
            .build()
        transformer.start(composition, sortie)
        principal.post(releve)
    }
}
