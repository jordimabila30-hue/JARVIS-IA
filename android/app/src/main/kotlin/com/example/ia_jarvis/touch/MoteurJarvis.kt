package com.example.ia_jarvis.touch

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import com.example.ia_jarvis.voix.DetecteurIntervention

/**
 * Le moteur Flutter de JARVIS, unique pour tout le processus. Il appartient
 * au processus et non à l'activité : quand l'activité est détruite
 * (retour, nettoyage du système) pendant que JARVIS Touch est actif, la
 * conversation, l'IA et la session continuent de vivre pour le mini-chat.
 * Aucun second moteur n'est jamais créé.
 */
object MoteurJarvis {
    private const val ID = "jarvis_principal"

    fun obtenir(contexte: Context, arguments: Array<String>?): FlutterEngine {
        FlutterEngineCache.getInstance().get(ID)?.let { return it }
        val moteur = FlutterEngine(contexte.applicationContext, arguments)
        FlutterEngineCache.getInstance().put(ID, moteur)
        CanalMiniChat.attacher(moteur.dartExecutor.binaryMessenger)
        // Interruption automatique (expérimentale) : détection lié au moteur.
        DetecteurIntervention(moteur.dartExecutor.binaryMessenger)
        return moteur
    }

    /**
     * Ni activité ni bulle : le moteur n'a plus de raison d'exister
     * (comportement d'avant JARVIS Touch : il meurt avec l'application).
     */
    fun libererSiInutile(activiteVivante: Boolean) {
        if (activiteVivante || ServiceJarvisTouch.actif) return
        val moteur = FlutterEngineCache.getInstance().get(ID) ?: return
        CanalMiniChat.detacher()
        FlutterEngineCache.getInstance().remove(ID)
        moteur.destroy()
    }
}

/**
 * Canal `jarvis/touch_chat` vers la conversation (côté Dart :
 * `PasserelleMiniChat`). Lié au moteur, pas à une activité.
 */
object CanalMiniChat {
    private var canal: MethodChannel? = null

    /** Fenêtre du mini-chat ouverte : reçoit `etat` et `fragment`. */
    var recepteur: ((String, Any?) -> Unit)? = null

    /** Fenêtre du vocal flottant ouverte : reçoit `vocal`, `niveau` et
     *  `vocalCommande` (« réduis la fenêtre », « ferme le vocal »). */
    var recepteurVocal: ((String, Any?) -> Unit)? = null

    fun attacher(messager: BinaryMessenger) {
        canal = MethodChannel(messager, "jarvis/touch_chat").apply {
            setMethodCallHandler { appel, resultat ->
                if (appel.method == "vocal" || appel.method == "niveau" || appel.method == "vocalCommande") {
                    recepteurVocal?.invoke(appel.method, appel.arguments)
                } else {
                    recepteur?.invoke(appel.method, appel.arguments)
                }
                resultat.success(null)
            }
        }
    }

    fun detacher() {
        canal?.setMethodCallHandler(null)
        canal = null
    }

    /** [echec] : JARVIS absent (moteur détruit, accueil non affiché…). */
    fun appeler(methode: String, arguments: Any?, succes: (Any?) -> Unit, echec: (String?) -> Unit) {
        val c = canal ?: return echec(null)
        c.invokeMethod(methode, arguments, object : MethodChannel.Result {
            override fun success(result: Any?) = succes(result)
            override fun error(code: String, message: String?, details: Any?) = echec(message)
            override fun notImplemented() = echec(null)
        })
    }
}
