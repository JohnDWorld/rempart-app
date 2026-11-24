package com.sovereign.rempart_app

import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.speech.RecognitionListener
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import androidx.annotation.RequiresApi
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Transcription d'un vocal, sur l'appareil seulement.
 *
 * Le reconnaisseur « sur l'appareil » d'Android (createOnDeviceSpeechRecognizer)
 * ne laisse rien partir : c'est la seule raison de ce choix, le reconnaisseur
 * ordinaire de Google enverrait le son a ses serveurs. Il lit un fichier
 * depuis Android 13 (EXTRA_AUDIO_SOURCE), en PCM brut : le M4A du vocal est
 * donc decode ici, ramene en mono a 16 kHz, puis verse dans un tube.
 *
 * EXTRA_SEGMENTED_SESSION fait transcrire le fichier entier : sans elle, le
 * reconnaisseur s'arrete au premier silence.
 *
 * Piege (2026-11-24) : le reconnaisseur est fait pour un flux en direct. Le
 * fichier verse d'un coup, il lisait 12 s de son en 6 ms, concluait aussitot
 * et rendait « aucune parole » sur une voix parfaitement nette. Le son part
 * donc par tranches de 100 ms, a [ACCELERATION] fois le rythme reel.
 */
object Transcription {
    private const val TAG = "Transcription"
    private const val TAUX = 16000
    // ponytail: 4x valide sur l'emulateur (12 s transcrites en 2,9 s, meme
    // texte qu'au rythme reel) ; si un telephone lent rend « aucune parole »,
    // descendre ici.
    private const val ACCELERATION = 4L

    fun disponible(contexte: Context): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            SpeechRecognizer.isOnDeviceRecognitionAvailable(contexte)

    /**
     * Transcrit [chemin] en [langue] ; [fin] recoit le texte ou une erreur
     * (code, message), toujours sur le fil principal.
     */
    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    fun transcrire(
        contexte: Context,
        chemin: String,
        langue: String,
        fin: (texte: String?, code: String?, message: String?) -> Unit,
    ) {
        val principal = Handler(Looper.getMainLooper())
        Executors.newSingleThreadExecutor().execute {
            val pcm = try {
                decoder(chemin)
            } catch (e: Exception) {
                principal.post { fin(null, "decodage", e.message) }
                return@execute
            }
            Log.i(TAG, "vocal decode : ${pcm.size} octets de PCM")
            principal.post { reconnaitre(contexte, pcm, langue, fin) }
        }
    }

    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    private fun reconnaitre(
        contexte: Context,
        pcm: ByteArray,
        langue: String,
        fin: (String?, String?, String?) -> Unit,
    ) {
        val reconnaisseur = SpeechRecognizer.createOnDeviceSpeechRecognizer(contexte)
        val tube = ParcelFileDescriptor.createPipe()
        val intention = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, langue)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, tube[0])
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
            putExtra(
                RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING,
                AudioFormat.ENCODING_PCM_16BIT,
            )
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, TAUX)
            putExtra(
                RecognizerIntent.EXTRA_SEGMENTED_SESSION,
                RecognizerIntent.EXTRA_AUDIO_SOURCE,
            )
        }
        val morceaux = mutableListOf<String>()
        val fini = AtomicBoolean(false)
        fun terminer(texte: String?, code: String?, message: String?) {
            if (!fini.compareAndSet(false, true)) return
            reconnaisseur.destroy()
            runCatching { tube[0].close() }
            fin(texte, code, message)
        }
        fun garder(resultats: Bundle?) {
            resultats?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull()?.trim()?.takeIf { it.isNotEmpty() }
                ?.let { morceaux += it }
        }
        reconnaisseur.setRecognitionListener(object : RecognitionListener {
            override fun onSegmentResults(resultats: Bundle) = garder(resultats)
            override fun onEndOfSegmentedSession() =
                terminer(morceaux.joinToString(" "), null, null)
            override fun onResults(resultats: Bundle?) {
                garder(resultats)
                terminer(morceaux.joinToString(" "), null, null)
            }
            override fun onError(erreur: Int) {
                Log.w(TAG, "erreur du reconnaisseur : $erreur")
                when {
                    // Fin du fichier sans parole reconnue apres coup : ce qui
                    // a ete compris jusque-la vaut reponse.
                    morceaux.isNotEmpty() ->
                        terminer(morceaux.joinToString(" "), null, null)
                    erreur == SpeechRecognizer.ERROR_NO_MATCH ||
                        erreur == SpeechRecognizer.ERROR_SPEECH_TIMEOUT ->
                        terminer("", null, null)
                    erreur == SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED ||
                        erreur == SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE -> {
                        // Modele de la langue absent : on lance son
                        // telechargement, la prochaine tentative passera.
                        // Une intention neuve : celle de l'ecoute porte le
                        // tube, deja ferme, et la demande echouait sur un
                        // « Bad file descriptor ».
                        val telechargement = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                            .putExtra(RecognizerIntent.EXTRA_LANGUAGE, langue)
                        runCatching { reconnaisseur.triggerModelDownload(telechargement) }
                        terminer(null, "langue", "modele $langue absent ($erreur)")
                    }
                    else -> terminer(null, "reconnaissance", "erreur $erreur")
                }
            }
            override fun onReadyForSpeech(p: Bundle?) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rms: Float) {}
            override fun onBufferReceived(b: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onPartialResults(p: Bundle?) {}
            override fun onEvent(type: Int, p: Bundle?) {}
        })
        reconnaisseur.checkRecognitionSupport(
            intention,
            Executors.newSingleThreadExecutor(),
            object : RecognitionSupportCallback {
                override fun onSupportResult(support: RecognitionSupport) {
                    Log.i(
                        TAG,
                        "langues installees ${support.installedOnDeviceLanguages}, " +
                            "en attente ${support.pendingOnDeviceLanguages}, " +
                            "disponibles ${support.supportedOnDeviceLanguages}",
                    )
                }

                override fun onError(erreur: Int) {
                    Log.w(TAG, "support inconnu : $erreur")
                }
            },
        )
        // Le tube s'ecrit a part, au rythme impose plus haut.
        Thread {
            runCatching {
                ParcelFileDescriptor.AutoCloseOutputStream(tube[1]).use { sortie ->
                    val tranche = TAUX * 2 / 10 // 100 ms de PCM 16 bits mono
                    var i = 0
                    while (i < pcm.size && !fini.get()) {
                        val n = minOf(tranche, pcm.size - i)
                        sortie.write(pcm, i, n)
                        i += n
                        Thread.sleep(100L / ACCELERATION)
                    }
                }
            }.onFailure { Log.w(TAG, "tube interrompu : ${it.message}") }
        }.start()
        reconnaisseur.startListening(intention)
    }

    /** Decode un fichier audio en PCM 16 bits mono a [TAUX] Hz. */
    private fun decoder(chemin: String): ByteArray {
        val extracteur = MediaExtractor()
        extracteur.setDataSource(chemin)
        val piste = (0 until extracteur.trackCount).first {
            extracteur.getTrackFormat(it).getString(MediaFormat.KEY_MIME)
                ?.startsWith("audio/") == true
        }
        extracteur.selectTrack(piste)
        val format = extracteur.getTrackFormat(piste)
        val decodeur = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
        decodeur.configure(format, null, null, 0)
        decodeur.start()
        val brut = ByteArrayOutputStream()
        var taux = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        var canaux = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        val info = MediaCodec.BufferInfo()
        var finEntree = false
        try {
            while (true) {
                if (!finEntree) {
                    val i = decodeur.dequeueInputBuffer(10_000)
                    if (i >= 0) {
                        val n = extracteur.readSampleData(decodeur.getInputBuffer(i)!!, 0)
                        if (n < 0) {
                            decodeur.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            finEntree = true
                        } else {
                            decodeur.queueInputBuffer(i, 0, n, extracteur.sampleTime, 0)
                            extracteur.advance()
                        }
                    }
                }
                val o = decodeur.dequeueOutputBuffer(info, 10_000)
                if (o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    taux = decodeur.outputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    canaux = decodeur.outputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                } else if (o >= 0) {
                    val tampon = decodeur.getOutputBuffer(o)!!
                    val octets = ByteArray(info.size)
                    tampon.position(info.offset)
                    tampon.get(octets)
                    brut.write(octets)
                    decodeur.releaseOutputBuffer(o, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                }
            }
        } finally {
            decodeur.stop()
            decodeur.release()
            extracteur.release()
        }
        return reechantillonner(brut.toByteArray(), taux, canaux)
    }

    /** Ramene du PCM 16 bits entrelace en mono a [TAUX] Hz (interpolation lineaire). */
    private fun reechantillonner(pcm: ByteArray, taux: Int, canaux: Int): ByteArray {
        val entree = ByteBuffer.wrap(pcm).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()
        val trames = entree.remaining() / canaux
        val mono = FloatArray(trames) { t ->
            var somme = 0f
            for (c in 0 until canaux) somme += entree.get(t * canaux + c)
            somme / canaux
        }
        val sortie = ((trames.toLong() * TAUX) / taux).toInt()
        val resultat = ByteBuffer.allocate(sortie * 2).order(ByteOrder.LITTLE_ENDIAN)
        for (i in 0 until sortie) {
            val x = i.toDouble() * taux / TAUX
            val a = x.toInt().coerceAtMost(trames - 1)
            val b = (a + 1).coerceAtMost(trames - 1)
            val f = (x - a).toFloat()
            resultat.putShort((mono[a] * (1 - f) + mono[b] * f).toInt().toShort())
        }
        return resultat.array()
    }
}
