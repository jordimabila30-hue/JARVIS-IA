package com.example.ia_jarvis.touch.capture

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionConfig
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle

/**
 * Demande le consentement Android à la capture (une fois par capture).
 *
 * Transparente, sans animation, dans SA tâche (`taskAffinity` à part,
 * `singleInstance`, hors des récents) : la lancer ne ramène jamais
 * JARVIS au premier plan, et en la refermant on retrouve l'application
 * que l'utilisateur consultait (c'est elle qui sera capturée).
 */
class ActiviteCaptureEcran : Activity() {

    private companion object {
        const val DEMANDE = 4109
    }

    private var repondu = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Recréée (rare : configChanges) : la demande est déjà affichée.
        if (savedInstanceState != null) return
        val gestionnaire = getSystemService(MediaProjectionManager::class.java)
        val demande = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // Android 14+ : l'écran entier (pas une seule application).
            gestionnaire.createScreenCaptureIntent(MediaProjectionConfig.createConfigForDefaultDisplay())
        } else {
            gestionnaire.createScreenCaptureIntent()
        }
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(demande, DEMANDE)
        } catch (_: Exception) {
            repondu = true
            CaptureEcran.terminer(CaptureEcran.Issue.Echec("La capture d’écran n’est pas disponible sur cet appareil."))
            fermer()
        }
    }

    @Deprecated("Consentement MediaProjection (startActivityForResult).")
    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != DEMANDE) return super.onActivityResult(requestCode, resultCode, data)
        repondu = true
        if (resultCode == RESULT_OK && data != null) {
            CaptureEcran.autorisee(this, resultCode, data)
        } else {
            CaptureEcran.terminer(CaptureEcran.Issue.Annulee)
        }
        fermer()
    }

    override fun onDestroy() {
        // Fermée sans réponse (Accueil, autre appli…) : retour à la bulle.
        if (!repondu) CaptureEcran.terminer(CaptureEcran.Issue.Annulee)
        super.onDestroy()
    }

    private fun fermer() {
        finish()
        @Suppress("DEPRECATION")
        overridePendingTransition(0, 0)
    }
}
