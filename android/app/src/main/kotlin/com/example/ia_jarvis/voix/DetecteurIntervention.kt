package com.example.ia_jarvis.voix

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AutomaticGainControl
import android.media.audiofx.NoiseSuppressor
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.sqrt

/**
 * Détection d'une intervention de l'utilisateur PENDANT que JARVIS parle
 * (interruption automatique, EXPÉRIMENTALE). Canal `jarvis/voix_detection`.
 *
 * Micro en mode communication (VOICE_COMMUNICATION) avec, si l'appareil
 * les fournit, l'annulation d'écho (AEC) et la réduction de bruit : la
 * voix de JARVIS (haut-parleur) est en partie retirée. Jamais un simple pic
 * de volume : une intervention exige, sur ~0,3 s, une énergie nettement
 * au-dessus du fond calibré PENDANT la voix de JARVIS, durable (12 trames
 * de 20 ms sur 16) et de structure vocale (taux de passages par zéro).
 * Événements vers Dart : `candidat` (mesures jointes), `fin` (statistiques
 * de la séance). Aucune donnée audio n'est gardée ni envoyée.
 */
class DetecteurIntervention(messager: BinaryMessenger) : MethodChannel.MethodCallHandler {

    private companion object {
        const val TAG = "JarvisDetection"
        const val TAUX = 16000
        const val TRAME = 320 // 20 ms
        const val CALIBRATION_MS = 500L
        const val ECART_DB = 10.0
        const val FENETRE = 16
        const val REQUIS = 12
        const val REPOS_MS = 1500L
    }

    private val canal = MethodChannel(messager, "jarvis/voix_detection")
    private val principal = Handler(Looper.getMainLooper())
    @Volatile private var actif = false
    private var fil: Thread? = null

    init {
        canal.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "demarrer" -> result.success(demarrer())
            "arreter" -> {
                arreter()
                result.success(null)
            }
            "capacites" -> result.success(
                mapOf(
                    "aec" to AcousticEchoCanceler.isAvailable(),
                    "ns" to NoiseSuppressor.isAvailable(),
                )
            )
            else -> result.notImplemented()
        }
    }

    @SuppressLint("MissingPermission")
    private fun demarrer(): Map<String, Any?> {
        arreter()
        val min = AudioRecord.getMinBufferSize(TAUX, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val enregistreur = try {
            AudioRecord(
                MediaRecorder.AudioSource.VOICE_COMMUNICATION, TAUX,
                AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, max(min, TRAME * 8),
            )
        } catch (e: Exception) {
            Log.w(TAG, "micro indisponible (${e.javaClass.simpleName})")
            return mapOf("ok" to false)
        }
        if (enregistreur.state != AudioRecord.STATE_INITIALIZED) {
            enregistreur.release()
            return mapOf("ok" to false)
        }
        val session = enregistreur.audioSessionId
        val aec = if (AcousticEchoCanceler.isAvailable()) AcousticEchoCanceler.create(session)?.apply { enabled = true } else null
        val ns = if (NoiseSuppressor.isAvailable()) NoiseSuppressor.create(session)?.apply { enabled = true } else null
        // Gain automatique coupé : il remonterait l'écho résiduel.
        val agc = if (AutomaticGainControl.isAvailable()) AutomaticGainControl.create(session)?.apply { enabled = false } else null
        actif = true
        val t = Thread({ boucle(enregistreur, aec, ns, agc) }, "JarvisDetection")
        fil = t
        t.start()
        return mapOf("ok" to true, "aec" to (aec?.enabled == true), "ns" to (ns?.enabled == true))
    }

    fun arreter() {
        actif = false
        fil?.join(300)
        fil = null
    }

    private fun boucle(r: AudioRecord, aec: AcousticEchoCanceler?, ns: NoiseSuppressor?, agc: AutomaticGainControl?) {
        val tampon = ShortArray(TRAME)
        val voix = BooleanArray(FENETRE)
        var i = 0
        var trames = 0
        var candidats = 0
        var fond = -90.0
        val calibration = ArrayList<Double>()
        val debut = SystemClock.elapsedRealtime()
        var dernier = 0L
        var maxEcart = -99.0
        try {
            r.startRecording()
            while (actif) {
                val n = r.read(tampon, 0, TRAME)
                if (n <= 0) continue
                trames++
                var somme = 0.0
                var passages = 0
                for (k in 0 until n) {
                    val v = tampon[k].toDouble()
                    somme += v * v
                    if (k > 0 && (tampon[k] >= 0) != (tampon[k - 1] >= 0)) passages++
                }
                val db = 20 * log10(sqrt(somme / n) / 32768.0 + 1e-9)
                val zcr = passages.toDouble() / n
                val maintenant = SystemClock.elapsedRealtime()
                if (maintenant - debut < CALIBRATION_MS) {
                    // Fond calibré PENDANT la voix de JARVIS (écho résiduel compris).
                    calibration.add(db)
                    continue
                }
                if (calibration.isNotEmpty()) {
                    calibration.sort()
                    fond = calibration[calibration.size * 3 / 4]
                    calibration.clear()
                }
                val ecart = db - fond
                if (ecart > maxEcart) maxEcart = ecart
                val vocal = ecart > ECART_DB && zcr in 0.02..0.35
                voix[i % FENETRE] = vocal
                i++
                // Fond lent (trames non vocales seulement).
                if (!vocal) fond = fond * 0.98 + db * 0.02
                if (i >= FENETRE && voix.count { it } >= REQUIS && maintenant - dernier > REPOS_MS) {
                    dernier = maintenant
                    candidats++
                    val m = mapOf("ecartDb" to ecart, "fondDb" to fond, "zcr" to zcr,
                        "apresMs" to (maintenant - debut))
                    Log.i(TAG, "candidat : écart ${"%.1f".format(ecart)} dB, fond ${"%.1f".format(fond)} dB")
                    principal.post { canal.invokeMethod("candidat", m) }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "détection interrompue (${e.javaClass.simpleName})")
        } finally {
            try {
                r.stop()
            } catch (_: Exception) {
            }
            aec?.release()
            ns?.release()
            agc?.release()
            r.release()
            val stats = mapOf("trames" to trames, "candidats" to candidats, "maxEcartDb" to maxEcart,
                "fondDb" to fond, "aec" to (aec != null))
            Log.i(TAG, "séance : $trames trames, $candidats candidat(s), écart max ${"%.1f".format(maxEcart)} dB")
            principal.post { canal.invokeMethod("fin", stats) }
        }
    }
}
