package com.example.ia_jarvis.touch.capture

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Rect
import java.io.File
import java.util.UUID

/**
 * Une capture d'écran de JARVIS Touch, en mémoire et dans le cache privé.
 * Le recadrage n'est appliqué qu'à la validation ([valider]) : les pixels
 * gardés sont copiés tels quels (aucun agrandissement), puis l'image
 * d'origine et son fichier sont libérés. Rien n'est envoyé : la phase 3B
 * lira [fichierValide] après une action explicite de l'utilisateur.
 *
 * Utilisée sur le thread principal seulement. La vue qui affiche [image]
 * doit l'avoir lâchée avant [valider] ou [supprimer] (les images
 * remplacées sont libérées après leur écriture, sur le fil du dépôt).
 */
class CaptureTouch(private val contexte: Context, image: Bitmap) {

    val id: String = UUID.randomUUID().toString()

    var image: Bitmap = image
        private set

    /** Vrai après « Valider » : prête pour une future utilisation. */
    var validee = false
        private set

    var supprimee = false
        private set

    private var fichier: File? = null
    private var version = 0

    init {
        ecrire(image)
    }

    private fun ecrire(b: Bitmap) {
        val v = ++version
        val nom = if (v == 1) "capture_$id" else "capture_${id}_$v"
        DepotCaptures.ecrire(contexte, b, nom) { f ->
            // Image remplacée ou capture supprimée entre-temps.
            if (supprimee || v != version) DepotCaptures.supprimer(listOf(f)) else fichier = f
        }
    }

    /**
     * Garde la zone [z] (pixels de l'image, bornée) et marque la capture
     * validée. Faux si la mémoire manque (l'image n'a pas changé).
     */
    fun valider(z: Rect): Boolean {
        if (supprimee) return false
        val borne = Rect(z)
        if (!borne.intersect(0, 0, image.width, image.height) || borne.width() < 2 || borne.height() < 2) {
            return false
        }
        if (borne.width() < image.width || borne.height() < image.height) {
            val recadree = try {
                Bitmap.createBitmap(image, borne.left, borne.top, borne.width(), borne.height())
            } catch (_: OutOfMemoryError) {
                return false
            }
            val ancienne = image
            val ancienFichier = fichier
            image = recadree
            fichier = null
            ecrire(recadree)
            DepotCaptures.supprimer(listOf(ancienFichier), listOf(ancienne))
        }
        validee = true
        return true
    }

    /** Abandon : fichiers effacés et image libérée. */
    fun supprimer() {
        if (supprimee) return
        supprimee = true
        DepotCaptures.supprimer(listOf(fichier), listOf(image))
        fichier = null
    }

    /**
     * Phase 3B : fichier PNG de la capture validée, une fois son écriture
     * terminée ; null si elle n'est pas validée ou a été supprimée.
     */
    fun fichierValide(rappel: (File?) -> Unit) {
        DepotCaptures.apres { rappel(if (supprimee || !validee) null else fichier) }
    }
}
