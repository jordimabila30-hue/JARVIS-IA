package com.example.ia_jarvis

import android.content.Context
import android.content.Intent
import android.os.Bundle
import com.example.ia_jarvis.touch.MoteurJarvis
import com.example.ia_jarvis.touch.PontJarvisTouch
import com.example.ia_jarvis.touch.ServiceJarvisTouch
import com.example.ia_jarvis.touch.capture.DepotCaptures
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    companion object {
        /** Activités vivantes (le moteur partagé n'est libéré qu'à zéro). */
        var vivantes = 0
            private set
    }

    // Import WhatsApp : partages reçus et sélecteur de documents.
    private var importation: PontImportation? = null
    // JARVIS Touch : bulle flottante (autorisation, démarrage, arrêt).
    private var touch: PontJarvisTouch? = null

    // JARVIS Touch : moteur du processus, partagé avec le mini-chat. Il
    // survit à l'activité tant que la bulle est active (conversation,
    // réponse en cours et session gardées) ; jamais de second moteur.
    override fun provideFlutterEngine(context: Context): FlutterEngine =
        MoteurJarvis.obtenir(context, flutterShellArgs.toArray())

    // Libéré à la main (onDestroy) : seulement si la bulle n'en a plus besoin.
    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        importation = PontImportation(this, flutterEngine.dartExecutor.binaryMessenger)
        touch = PontJarvisTouch(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        vivantes++
        super.onCreate(savedInstanceState)
        // Captures de JARVIS Touch abandonnées (arrêt inattendu) : effacées.
        if (!ServiceJarvisTouch.actif) DepotCaptures.nettoyerTout(this)
        // Lancement à froid par un partage. Activité recréée (état
        // restauré) : ce partage a déjà été traité.
        if (savedInstanceState == null) importation?.recevoir(intent)
    }

    override fun onResume() {
        super.onResume()
        // Même conversation à l'écran : le mini-chat n'a plus lieu d'être.
        ServiceJarvisTouch.reduireChat()
    }

    // JARVIS déjà ouvert (singleTask) : le partage arrive ici.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        importation?.recevoir(intent)
    }

    @Deprecated("Sélecteur de documents (startActivityForResult).")
    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (importation?.surResultat(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        importation?.fermer()
        importation = null
        // La bulle reste affichée : elle vit dans son propre service.
        touch?.fermer()
        touch = null
        val quitte = isFinishing && !isChangingConfigurations
        super.onDestroy()
        vivantes--
        if (quitte) MoteurJarvis.libererSiInutile(activiteVivante = vivantes > 0)
    }
}
