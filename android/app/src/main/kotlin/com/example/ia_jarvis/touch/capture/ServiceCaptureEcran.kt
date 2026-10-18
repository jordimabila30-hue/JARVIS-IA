package com.example.ia_jarvis.touch.capture

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.util.DisplayMetrics
import android.util.Log
import android.view.Display
import com.example.ia_jarvis.R

/**
 * Capture de SECOURS (service d'accessibilité non activé ou Android < 11),
 * par MediaProjection : UNE image, jamais de
 * vidéo ni de son. Service au premier plan de type mediaProjection
 * (exigé depuis Android 10, déclaré avant la projection sur Android 14+),
 * vivant le temps d'une capture : projection, écran virtuel, lecteur
 * d'images et fil de traitement sont libérés dès l'image obtenue (ou à la
 * moindre erreur), puis le service s'arrête.
 *
 * Écran protégé (FLAG_SECURE) : Android rend une image noire ; elle est
 * refusée, jamais contournée.
 */
class ServiceCaptureEcran : Service() {

    companion object {
        const val EXTRA_CODE = "code"
        const val EXTRA_DONNEES = "donnees"
        private const val TAG = "JarvisCapture"
        private const val CANAL = "jarvis_touch"
        private const val ID_NOTIFICATION = 4108

        /** Dialogue de consentement et activité transparente refermés. */
        private const val DELAI_AVANT_IMAGE = 450L

        /** Aucune image dans ce délai : capture impossible. */
        private const val DELAI_MAX = 4000L
    }

    private val principal = Handler(Looper.getMainLooper())
    private var projection: MediaProjection? = null
    private var ecranVirtuel: VirtualDisplay? = null
    private var lecteur: ImageReader? = null
    private var fil: HandlerThread? = null
    private var rotationDepart = 0
    @Volatile
    private var imagePrise = false
    private var fini = false
    private var debut = 0L

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Toujours au premier plan d'abord (exigé dans les 5 s).
        try {
            passerAuPremierPlan()
        } catch (e: Exception) {
            Log.w(TAG, "premier plan refusé (${e.javaClass.simpleName})")
            finir(CaptureEcran.Issue.Echec("Android n’a pas permis la capture. Réessayez."))
            return START_NOT_STICKY
        }
        if (projection != null || fini) return START_NOT_STICKY
        debut = SystemClock.elapsedRealtime()
        val code = intent?.getIntExtra(EXTRA_CODE, Activity.RESULT_CANCELED) ?: Activity.RESULT_CANCELED
        val donnees: Intent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent?.getParcelableExtra(EXTRA_DONNEES, Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent?.getParcelableExtra(EXTRA_DONNEES)
        }
        if (code != Activity.RESULT_OK || donnees == null) {
            finir(CaptureEcran.Issue.Annulee)
            return START_NOT_STICKY
        }
        val p = try {
            getSystemService(MediaProjectionManager::class.java).getMediaProjection(code, donnees)
        } catch (e: Exception) {
            Log.w(TAG, "projection refusée (${e.javaClass.simpleName})")
            null
        }
        if (p == null) {
            finir(CaptureEcran.Issue.Echec("Android n’a pas permis la capture. Réessayez."))
            return START_NOT_STICKY
        }
        projection = p
        // Obligatoire avant l'écran virtuel (Android 14+) ; arrêt venu du
        // système (puce « diffusion » de la barre d'état, verrouillage…).
        p.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                if (!imagePrise) finir(CaptureEcran.Issue.Echec("La capture a été interrompue."))
            }
        }, principal)
        principal.postDelayed({ lancer() }, DELAI_AVANT_IMAGE)
        principal.postDelayed({
            if (!imagePrise) finir(CaptureEcran.Issue.Echec("La capture n’a pas pu être prise. Réessayez."))
        }, DELAI_MAX)
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        liberer()
        // Arrêt inattendu pendant la capture : la bulle revient quand même.
        if (!fini) CaptureEcran.terminer(CaptureEcran.Issue.Echec("La capture a été interrompue."))
        fini = true
        super.onDestroy()
    }

    // ── Capture ─────────────────────────────────────────────────────────

    private fun lancer() {
        val p = projection ?: return
        if (fini) return
        val ecran = getSystemService(DisplayManager::class.java).getDisplay(Display.DEFAULT_DISPLAY)
        val mesures = DisplayMetrics()
        @Suppress("DEPRECATION")
        ecran.getRealMetrics(mesures)
        val largeur = mesures.widthPixels
        val hauteur = mesures.heightPixels
        rotationDepart = ecran.rotation
        try {
            val f = HandlerThread("JarvisCapture").also { it.start() }
            fil = f
            // Deux tampons : le minimum utile ; aucun n'est gardé.
            val l = ImageReader.newInstance(largeur, hauteur, PixelFormat.RGBA_8888, 2)
            lecteur = l
            l.setOnImageAvailableListener({ traiter(it, largeur, hauteur) }, Handler(f.looper))
            ecranVirtuel = p.createVirtualDisplay(
                "JarvisCapture", largeur, hauteur, mesures.densityDpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                l.surface, null, null,
            )
        } catch (e: Exception) {
            Log.w(TAG, "écran virtuel impossible (${e.javaClass.simpleName})")
            finir(CaptureEcran.Issue.Echec("La capture n’a pas pu être prise. Réessayez."))
        }
    }

    /** Fil de capture : première image seulement, convertie puis rendue. */
    private fun traiter(l: ImageReader, largeur: Int, hauteur: Int) {
        if (imagePrise) return
        val image = try {
            l.acquireLatestImage()
        } catch (_: Exception) {
            null
        } ?: return
        imagePrise = true
        val recue = SystemClock.elapsedRealtime()
        var resultat: Bitmap? = null
        var issue: CaptureEcran.Issue
        try {
            val plan = image.planes[0]
            val pas = plan.pixelStride
            val largeurTampon = plan.rowStride / pas
            val brute = Bitmap.createBitmap(largeurTampon, hauteur, Bitmap.Config.ARGB_8888)
            brute.copyPixelsFromBuffer(plan.buffer)
            // Lignes complétées par le pilote : on retire la marge à droite.
            resultat = if (largeurTampon == largeur) brute else {
                Bitmap.createBitmap(brute, 0, 0, largeur, hauteur).also { brute.recycle() }
            }
            issue = CaptureEcran.Issue.Reussie(resultat)
        } catch (_: OutOfMemoryError) {
            issue = CaptureEcran.Issue.Echec(CaptureEcran.MESSAGE_MEMOIRE)
        } catch (e: Exception) {
            Log.w(TAG, "conversion impossible (${e.javaClass.simpleName})")
            issue = CaptureEcran.Issue.Echec("La capture n’a pas pu être lue. Réessayez.")
        } finally {
            image.close()
        }
        val ecran = getSystemService(DisplayManager::class.java).getDisplay(Display.DEFAULT_DISPLAY)
        if (resultat != null && ecran.rotation != rotationDepart) {
            resultat.recycle()
            resultat = null
            issue = CaptureEcran.Issue.Echec("L’écran a tourné pendant la capture. Réessayez.")
        }
        if (resultat != null && CaptureEcran.estNoire(resultat)) {
            resultat.recycle()
            issue = CaptureEcran.Issue.Echec(CaptureEcran.MESSAGE_NOIRE)
        }
        // Mesures seulement (jamais le contenu).
        Log.i(TAG, "image ${largeur}×${hauteur} : consentement → image " +
            "${recue - debut} ms, conversion ${SystemClock.elapsedRealtime() - recue} ms")
        principal.post { finir(issue) }
    }

    // ── Fin ─────────────────────────────────────────────────────────────

    private fun finir(issue: CaptureEcran.Issue) {
        if (fini) {
            if (issue is CaptureEcran.Issue.Reussie) issue.image.recycle()
            return
        }
        fini = true
        liberer()
        CaptureEcran.terminer(issue)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    /** Tout ce qui tient l'écran ou de la mémoire graphique, libéré. */
    private fun liberer() {
        principal.removeCallbacksAndMessages(null)
        imagePrise = true
        try {
            ecranVirtuel?.release()
        } catch (_: Exception) {
        }
        ecranVirtuel = null
        try {
            lecteur?.setOnImageAvailableListener(null, null)
            lecteur?.close()
        } catch (_: Exception) {
        }
        lecteur = null
        val p = projection
        projection = null
        try {
            p?.stop()
        } catch (_: Exception) {
        }
        fil?.quitSafely()
        fil = null
    }

    private fun passerAuPremierPlan() {
        val gestionnaire = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Même canal discret que la bulle (aucune icône dans la barre
            // d'état : elle apparaîtrait sur la capture).
            if (gestionnaire.getNotificationChannel(CANAL) == null) {
                gestionnaire.createNotificationChannel(
                    NotificationChannel(CANAL, "JARVIS Touch", NotificationManager.IMPORTANCE_MIN).apply {
                        setShowBadge(false)
                    }
                )
            }
        }
        val constructeur = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CANAL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this).setPriority(Notification.PRIORITY_MIN)
        }
        val notification = constructeur
            .setSmallIcon(R.drawable.ic_jarvis_touch)
            .setContentTitle("JARVIS Touch")
            .setContentText("Capture de l’écran en cours (une seule image)")
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(ID_NOTIFICATION, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(ID_NOTIFICATION, notification)
        }
    }
}
