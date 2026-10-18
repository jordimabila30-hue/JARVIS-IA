package com.example.ia_jarvis.touch

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import com.example.ia_jarvis.touch.capture.CaptureEcran
import com.example.ia_jarvis.touch.capture.ServiceAccessibiliteJarvis
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Canal `jarvis/touch` : autorisation de superposition, démarrage et
 * arrêt de [ServiceJarvisTouch], état réel de la capture d'écran
 * (Paramètres › Général › JARVIS Touch › Capture d'écran). `demarrer` ne répond qu'une fois la bulle
 * réellement affichée (ou en échec).
 */
class PontJarvisTouch(
    private val activite: Activity,
    messager: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val canal = MethodChannel(messager, "jarvis/touch")
    private val principal = Handler(Looper.getMainLooper())

    init {
        canal.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "autorisationAccordee" -> result.success(autorise())
            "demanderAutorisation" -> demanderAutorisation(result)
            "demarrer" -> demarrer(result)
            "arreter" -> {
                activite.stopService(Intent(activite, ServiceJarvisTouch::class.java))
                result.success(null)
            }
            "estActif" -> result.success(ServiceJarvisTouch.actif)
            // Ce que le système permet vraiment : capture sans autorisation
            // à chaque fois (accessibilité activée par l'utilisateur) ou non.
            "etatCapture" -> result.success(
                mapOf(
                    "sansAutorisationPossible" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R),
                    "sansAutorisation" to ServiceAccessibiliteJarvis.disponible,
                )
            )
            "ouvrirReglagesCapture" -> {
                CaptureEcran.ouvrirReglagesAccessibilite(activite)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun autorise(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(activite)

    private fun demanderAutorisation(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(null)
            return
        }
        try {
            activite.startActivity(
                Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:${activite.packageName}"),
                )
            )
            result.success(null)
        } catch (e: Exception) {
            // Certains appareils n'acceptent pas l'écran propre à l'appli.
            try {
                activite.startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION))
                result.success(null)
            } catch (e2: Exception) {
                result.error("reglages", "Réglages d’Android indisponibles.", null)
            }
        }
    }

    private fun demarrer(result: MethodChannel.Result) {
        if (!autorise()) {
            result.error("autorisation", "Autorisation « Afficher par-dessus les autres applis » absente.", null)
            return
        }
        if (ServiceJarvisTouch.actif) {
            result.success(true)
            return
        }
        var repondu = false
        val delai = Runnable {
            if (repondu) return@Runnable
            repondu = true
            ServiceJarvisTouch.surDemarrage = null
            result.error("delai", "La bulle n’a pas répondu.", null)
        }
        ServiceJarvisTouch.surDemarrage = { ok, message ->
            principal.post {
                if (!repondu) {
                    repondu = true
                    principal.removeCallbacks(delai)
                    if (ok) result.success(true) else result.error("echec", message, null)
                }
            }
        }
        try {
            val intent = Intent(activite, ServiceJarvisTouch::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                activite.startForegroundService(intent)
            } else {
                activite.startService(intent)
            }
            principal.postDelayed(delai, 4000)
        } catch (e: Exception) {
            repondu = true
            ServiceJarvisTouch.surDemarrage = null
            result.error("echec", "Android a refusé de lancer JARVIS Touch.", null)
        }
    }

    fun fermer() {
        canal.setMethodCallHandler(null)
    }
}
