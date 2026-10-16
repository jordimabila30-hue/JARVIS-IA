package com.example.ia_jarvis.touch

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.content.res.Configuration
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.util.Log
import com.example.ia_jarvis.MainActivity
import com.example.ia_jarvis.R

/**
 * JARVIS Touch : service au premier plan qui garde la bulle flottante
 * affichée quand JARVIS passe en arrière-plan. Il ne fait rien d'autre
 * (ni micro, ni capture d'écran). Démarré et arrêté par [PontJarvisTouch].
 */
class ServiceJarvisTouch : Service() {

    companion object {
        private const val TAG = "JarvisTouch"
        private const val CANAL = "jarvis_touch"
        private const val ID_NOTIFICATION = 4107

        /** Vrai tant que la bulle est réellement affichée. */
        @Volatile
        var actif = false
            private set

        /** Résultat du démarrage, attendu par le pont (thread principal). */
        var surDemarrage: ((Boolean, String?) -> Unit)? = null
    }

    private var fenetres: FenetresJarvisTouch? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Une seule bulle, quel que soit le nombre de démarrages.
        if (fenetres != null) {
            signaler(true, null)
            return START_NOT_STICKY
        }
        // Obligatoire dans les 5 s après startForegroundService, même si
        // la bulle échoue ensuite.
        try {
            passerAuPremierPlan()
        } catch (e: Exception) {
            Log.e(TAG, "premier plan refusé", e)
            signaler(false, "Android a refusé de lancer JARVIS Touch.")
            stopSelf()
            return START_NOT_STICKY
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            signaler(false, "Autorisation « Afficher par-dessus les autres applis » absente.")
            stopSelf()
            return START_NOT_STICKY
        }
        try {
            fenetres = FenetresJarvisTouch(this).also { it.afficher() }
            actif = true
            signaler(true, null)
        } catch (e: Exception) {
            Log.e(TAG, "bulle impossible à afficher", e)
            fenetres?.retirer()
            fenetres = null
            signaler(false, "La bulle n’a pas pu s’afficher.")
            stopSelf()
        }
        // Pas de redémarrage automatique : JARVIS resynchronise au retour.
        return START_NOT_STICKY
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        fenetres?.surChangementEcran()
    }

    override fun onDestroy() {
        actif = false
        fenetres?.retirer()
        fenetres = null
        super.onDestroy()
    }

    private fun signaler(ok: Boolean, message: String?) {
        val rappel = surDemarrage ?: return
        surDemarrage = null
        rappel(ok, message)
    }

    private fun passerAuPremierPlan() {
        val gestionnaire = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            gestionnaire.createNotificationChannel(
                NotificationChannel(CANAL, "JARVIS Touch", NotificationManager.IMPORTANCE_MIN).apply {
                    description = "Garde la bulle JARVIS disponible au-dessus des applications."
                    setShowBadge(false)
                }
            )
        }
        val ouvrir = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val constructeur = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CANAL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this).setPriority(Notification.PRIORITY_MIN)
        }
        val notification = constructeur
            .setSmallIcon(R.drawable.ic_jarvis_touch)
            .setContentTitle("JARVIS Touch")
            .setContentText("Bulle active · désactivable dans Paramètres › Général")
            .setContentIntent(ouvrir)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(ID_NOTIFICATION, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(ID_NOTIFICATION, notification)
        }
    }
}
