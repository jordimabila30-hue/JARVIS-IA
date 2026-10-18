package com.example.ia_jarvis.touch.capture

import android.accessibilityservice.AccessibilityService
import android.graphics.Bitmap
import android.os.Build
import android.os.SystemClock
import android.util.Log
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import androidx.annotation.RequiresApi
import java.util.concurrent.Executors

/**
 * Capture sans fenêtre d'autorisation à chaque fois : l'utilisateur active
 * UNE fois « JARVIS Touch » dans Paramètres › Accessibilité, puis
 * « Analyser l'écran » prend l'image aussitôt (Android 11+,
 * `takeScreenshot`). Aucune projection, aucune icône de diffusion.
 *
 * Le service ne lit rien d'autre : aucun contenu des fenêtres
 * (`canRetrieveWindowContent="false"`), aucun événement traité, aucun
 * geste. Il ne prend une image que sur demande ([capturer]).
 */
class ServiceAccessibiliteJarvis : AccessibilityService() {

    companion object {
        private const val TAG = "JarvisCapture"

        /** Service activé et relié par Android (null sinon). */
        @Volatile
        var instance: ServiceAccessibiliteJarvis? = null
            private set

        /** Vrai si la capture peut se faire sans autorisation à chaque fois. */
        val disponible: Boolean
            get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && instance != null
    }

    private val fil = Executors.newSingleThreadExecutor { r -> Thread(r, "JarvisCaptureAcc") }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {}

    override fun onDestroy() {
        if (instance === this) instance = null
        fil.shutdown()
        super.onDestroy()
    }

    /** Une image de l'écran ; l'issue est rendue par [CaptureEcran.terminer]. */
    @RequiresApi(Build.VERSION_CODES.R)
    fun capturer() {
        val debut = SystemClock.elapsedRealtime()
        try {
            takeScreenshot(Display.DEFAULT_DISPLAY, fil, object : TakeScreenshotCallback {
                override fun onSuccess(resultat: ScreenshotResult) {
                    val recue = SystemClock.elapsedRealtime()
                    val tampon = resultat.hardwareBuffer
                    val issue = try {
                        // Image GPU → copie logicielle (recadrage, PNG), puis
                        // le tampon matériel est rendu aussitôt.
                        val gpu = Bitmap.wrapHardwareBuffer(tampon, resultat.colorSpace)
                        val image = gpu?.copy(Bitmap.Config.ARGB_8888, false)
                        gpu?.recycle()
                        when {
                            image == null -> CaptureEcran.Issue.Echec("La capture n’a pas pu être lue. Réessayez.")
                            CaptureEcran.estNoire(image) -> {
                                image.recycle()
                                CaptureEcran.Issue.Echec(CaptureEcran.MESSAGE_NOIRE)
                            }
                            else -> CaptureEcran.Issue.Reussie(image)
                        }
                    } catch (_: OutOfMemoryError) {
                        CaptureEcran.Issue.Echec(CaptureEcran.MESSAGE_MEMOIRE)
                    } catch (e: Exception) {
                        Log.w(TAG, "conversion impossible (${e.javaClass.simpleName})")
                        CaptureEcran.Issue.Echec("La capture n’a pas pu être lue. Réessayez.")
                    } finally {
                        tampon.close()
                    }
                    // Mesures seulement (jamais le contenu).
                    Log.i(TAG, "accessibilité : image en ${recue - debut} ms, " +
                        "copie ${SystemClock.elapsedRealtime() - recue} ms")
                    CaptureEcran.terminer(issue)
                }

                override fun onFailure(code: Int) {
                    Log.w(TAG, "takeScreenshot refusé (code $code)")
                    CaptureEcran.terminer(CaptureEcran.Issue.Echec(
                        when (code) {
                            ERROR_TAKE_SCREENSHOT_INTERVAL_TIME_SHORT ->
                                "Captures trop rapprochées : réessayez dans une seconde."
                            6 /* ERROR_TAKE_SCREENSHOT_SECURE_WINDOW (Android 14) */ ->
                                CaptureEcran.MESSAGE_NOIRE
                            else -> "La capture n’a pas pu être prise. Réessayez."
                        }
                    ))
                }
            })
        } catch (e: Exception) {
            Log.w(TAG, "takeScreenshot impossible (${e.javaClass.simpleName})")
            CaptureEcran.terminer(CaptureEcran.Issue.Echec("La capture n’a pas pu être prise. Réessayez."))
        }
    }
}
