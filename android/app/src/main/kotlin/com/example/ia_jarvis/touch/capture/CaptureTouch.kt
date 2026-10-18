package com.example.ia_jarvis.touch.capture

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Rect
import java.io.File
import java.util.UUID

/**
 * Une capture d'écran de JARVIS Touch, en mémoire et dans le cache privé :
 * l'image d'origine et, au plus, UN recadrage (toujours tiré de l'origine,
 * en pleine résolution : aucune perte). « Annuler le recadrage » revient à
 * l'origine. Rien n'est envoyé : la phase 3B lira [fichierValide] après
 * une action explicite de l'utilisateur.
 *
 * Utilisée sur le thread principal seulement. Avant [recadrer],
 * [annulerRecadrage] ou [supprimer], la vue qui affiche [actuelle] doit
 * l'avoir lâchée (les images remplacées sont libérées).
 */
class CaptureTouch(private val contexte: Context, val originale: Bitmap) {

    val id: String = UUID.randomUUID().toString()

    /** Zone retenue, en pixels de l'image d'origine (null : image entière). */
    var zone: Rect? = null
        private set

    private var recadree: Bitmap? = null
    private var fichierOriginal: File? = null
    private var fichierRecadre: File? = null
    private var version = 0
    var supprimee = false
        private set

    /** Image à montrer (et, plus tard, à transmettre si l'utilisateur le demande). */
    val actuelle: Bitmap get() = recadree ?: originale

    val recadrageApplique: Boolean get() = recadree != null

    init {
        DepotCaptures.ecrire(contexte, originale, "capture_$id") { f ->
            if (supprimee) DepotCaptures.supprimer(listOf(f)) else fichierOriginal = f
        }
    }

    /** Recadre l'origine sur [z] (bornée à l'image). Faux si la mémoire manque. */
    fun recadrer(z: Rect): Boolean {
        val borne = Rect(z)
        if (!borne.intersect(0, 0, originale.width, originale.height) || borne.width() < 2 || borne.height() < 2) {
            return false
        }
        if (borne.width() == originale.width && borne.height() == originale.height) {
            annulerRecadrage()
            return true
        }
        val image = try {
            Bitmap.createBitmap(originale, borne.left, borne.top, borne.width(), borne.height())
        } catch (_: OutOfMemoryError) {
            return false
        }
        oublierRecadrage()
        recadree = image
        zone = borne
        val v = ++version
        DepotCaptures.ecrire(contexte, image, "capture_${id}_recadree_$v") { f ->
            // Recadrage remplacé ou capture supprimée entre-temps.
            if (supprimee || v != version || recadree !== image) DepotCaptures.supprimer(listOf(f))
            else fichierRecadre = f
        }
        return true
    }

    fun annulerRecadrage() {
        oublierRecadrage()
        version++
    }

    private fun oublierRecadrage() {
        val ancienne = recadree ?: return
        DepotCaptures.supprimer(listOf(fichierRecadre), listOf(ancienne))
        recadree = null
        fichierRecadre = null
        zone = null
    }

    /** « Supprimer » : fichiers effacés et images libérées. */
    fun supprimer() {
        if (supprimee) return
        supprimee = true
        DepotCaptures.supprimer(listOf(fichierOriginal, fichierRecadre), listOf(recadree, originale))
        recadree = null
        fichierOriginal = null
        fichierRecadre = null
    }

    /**
     * Phase 3B : fichier PNG de l'image retenue (recadrée si un recadrage
     * est appliqué), une fois son écriture terminée ; null si supprimée.
     */
    fun fichierValide(rappel: (File?) -> Unit) {
        DepotCaptures.apres {
            rappel(if (supprimee) null else if (recadree != null) fichierRecadre else fichierOriginal)
        }
    }
}
