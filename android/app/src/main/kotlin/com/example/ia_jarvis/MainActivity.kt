package com.example.ia_jarvis

import android.content.Intent
import android.os.Bundle
import com.example.ia_jarvis.touch.PontJarvisTouch
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    // Import WhatsApp : partages reçus et sélecteur de documents.
    private var importation: PontImportation? = null
    // JARVIS Touch : bulle flottante (autorisation, démarrage, arrêt).
    private var touch: PontJarvisTouch? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        importation = PontImportation(this, flutterEngine.dartExecutor.binaryMessenger)
        touch = PontJarvisTouch(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Lancement à froid par un partage. Activité recréée (état
        // restauré) : ce partage a déjà été traité.
        if (savedInstanceState == null) importation?.recevoir(intent)
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
        super.onDestroy()
    }
}
