package com.example.ia_jarvis.touch.capture

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * Parcours « Analyser l'écran » de JARVIS Touch (phase 3A : capture
 * seulement, aucune IA, aucun envoi). Une seule capture à la fois.
 *
 * Voie principale : [ServiceAccessibiliteJarvis] activé une fois (Android
 * 11+) → image prise aussitôt, sans fenêtre d'autorisation.
 *
 * Secours (service non activé, Android < 11) : MediaProjection.
 * 1. [demarrer] : la bulle est déjà masquée ; [ActiviteCaptureEcran]
 *    (transparente, tâche à part) demande le consentement Android.
 * 2. Accord : [ServiceCaptureEcran] (premier plan, type mediaProjection)
 *    attend que le dialogue ait disparu, prend UNE image et arrête la
 *    projection aussitôt.
 * 3. [Issue] rendue au thread principal ([ecouteur] : les fenêtres de
 *    JARVIS Touch), qui affichent l'aperçu ou rendent la bulle.
 */
object CaptureEcran {
    private const val TAG = "JarvisCapture"

    const val MESSAGE_NOIRE =
        "L’image est noire : l’application affichée protège son contenu, ou l’écran était éteint."
    const val MESSAGE_MEMOIRE =
        "Mémoire insuffisante pour la capture. Fermez une application et réessayez."

    /** Bulle masquée : laisser une image s'afficher sans elle. */
    private const val DELAI_BULLE_MASQUEE = 150L

    sealed class Issue {
        class Reussie(val image: Bitmap) : Issue()
        class Echec(val message: String) : Issue()
        object Annulee : Issue()
    }

    private val principal = Handler(Looper.getMainLooper())

    /** Vrai du lancement à l'issue : empêche les captures simultanées. */
    @Volatile
    var enCours = false
        private set

    /** Fenêtres de JARVIS Touch (null : bulle arrêtée, résultat jeté). */
    var ecouteur: ((Issue) -> Unit)? = null

    /** Lance une capture (accessibilité, sinon consentement Android).
     *  Faux si une capture est déjà en cours. */
    fun demarrer(contexte: Context): Boolean {
        if (enCours) return false
        enCours = true
        val acces = ServiceAccessibiliteJarvis.instance
        if (acces != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            principal.postDelayed({
                if (enCours) acces.capturer()
            }, DELAI_BULLE_MASQUEE)
            return true
        }
        try {
            contexte.startActivity(
                Intent(contexte, ActiviteCaptureEcran::class.java).addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_NO_ANIMATION or
                        Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS
                )
            )
        } catch (e: Exception) {
            Log.w(TAG, "consentement impossible à demander (${e.javaClass.simpleName})")
            enCours = false
            return false
        }
        return true
    }

    /** Consentement accordé (appelé par l'activité, encore au premier plan :
     *  Android autorise alors le service de capture). */
    internal fun autorisee(contexte: Context, code: Int, donnees: Intent) {
        val service = Intent(contexte, ServiceCaptureEcran::class.java)
            .putExtra(ServiceCaptureEcran.EXTRA_CODE, code)
            .putExtra(ServiceCaptureEcran.EXTRA_DONNEES, donnees)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                contexte.startForegroundService(service)
            } else {
                contexte.startService(service)
            }
        } catch (e: Exception) {
            Log.w(TAG, "service de capture refusé (${e.javaClass.simpleName})")
            terminer(Issue.Echec("Android n’a pas permis la capture. Réessayez."))
        }
    }

    /** Écran protégé (FLAG_SECURE) : Android ne rend que du noir
     *  (échantillon de 12 × 12 points). */
    internal fun estNoire(b: Bitmap): Boolean {
        val n = 12
        for (i in 0 until n) {
            for (j in 0 until n) {
                val c = b.getPixel((b.width - 1) * i / (n - 1), (b.height - 1) * j / (n - 1))
                if ((c shr 16 and 0xFF) + (c shr 8 and 0xFF) + (c and 0xFF) > 24) return false
            }
        }
        return true
    }

    /** Ouvre Paramètres › Accessibilité (activer la capture sans autorisation). */
    fun ouvrirReglagesAccessibilite(contexte: Context) {
        try {
            contexte.startActivity(
                Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        } catch (_: Exception) {
        }
    }

    /** Fin du parcours (n'importe quel thread) : une seule issue est rendue. */
    internal fun terminer(issue: Issue) {
        principal.post {
            if (!enCours) {
                if (issue is Issue.Reussie) issue.image.recycle()
                return@post
            }
            enCours = false
            val rappel = ecouteur
            if (rappel == null) {
                // JARVIS Touch arrêté entre-temps : rien n'est gardé.
                if (issue is Issue.Reussie) issue.image.recycle()
            } else {
                rappel(issue)
            }
        }
    }
}
