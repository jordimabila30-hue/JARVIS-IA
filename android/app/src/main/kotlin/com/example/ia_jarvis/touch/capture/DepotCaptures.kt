package com.example.ia_jarvis.touch.capture

import android.content.Context
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

/**
 * Captures de JARVIS Touch : fichiers PNG TEMPORAIRES dans le cache privé
 * (`cache/captures_touch/`), jamais dans la galerie, jamais envoyés.
 *
 * Un seul fil pour tout (écriture, suppression, libération des images) :
 * les tâches s'exécutent dans l'ordre, donc une suppression passe toujours
 * après l'écriture du même fichier, et une image n'est jamais libérée
 * pendant qu'elle est encore encodée.
 */
object DepotCaptures {
    private const val TAG = "JarvisCapture"
    private const val DOSSIER = "captures_touch"

    private val fil = Executors.newSingleThreadExecutor { r ->
        Thread(r, "JarvisCaptureDepot").apply { priority = Thread.NORM_PRIORITY - 1 }
    }
    private val principal = Handler(Looper.getMainLooper())

    private fun dossier(contexte: Context) = File(contexte.cacheDir, DOSSIER)

    /** Écrit [image] (PNG, sans perte : texte lisible) ; rappel sur le
     *  thread principal avec le fichier, ou null si l'écriture échoue. */
    fun ecrire(contexte: Context, image: Bitmap, nom: String, rappel: (File?) -> Unit) {
        val app = contexte.applicationContext
        fil.execute {
            val debut = SystemClock.elapsedRealtime()
            val fichier = File(dossier(app).apply { mkdirs() }, "$nom.png")
            val ok = try {
                FileOutputStream(fichier).use { image.compress(Bitmap.CompressFormat.PNG, 100, it) }
            } catch (e: Exception) {
                Log.w(TAG, "écriture impossible (${e.javaClass.simpleName})")
                false
            }
            if (!ok) fichier.delete()
            // Mesure seulement (jamais le contenu).
            Log.i(TAG, "PNG ${image.width}×${image.height} : ${fichier.length() / 1024} Ko en " +
                "${SystemClock.elapsedRealtime() - debut} ms")
            principal.post { rappel(if (ok) fichier else null) }
        }
    }

    /** Efface des fichiers et libère des images, APRÈS les écritures en cours. */
    fun supprimer(fichiers: List<File?>, images: List<Bitmap?> = emptyList()) {
        fil.execute {
            fichiers.forEach { it?.delete() }
            images.forEach { if (it != null && !it.isRecycled) it.recycle() }
        }
    }

    /** Exécute [action] après toutes les tâches déjà demandées (fichiers à jour). */
    fun apres(action: () -> Unit) {
        fil.execute { principal.post(action) }
    }

    /** Captures abandonnées (arrêt inattendu, JARVIS Touch coupé) : tout effacer. */
    fun nettoyerTout(contexte: Context) {
        val app = contexte.applicationContext
        fil.execute {
            val restes = dossier(app).listFiles() ?: return@execute
            restes.forEach { it.delete() }
            if (restes.isNotEmpty()) Log.i(TAG, "${restes.size} capture(s) temporaire(s) effacée(s)")
        }
    }
}
