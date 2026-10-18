package com.example.ia_jarvis.touch

import android.animation.ValueAnimator
import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.PixelFormat
import android.graphics.Rect
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.DisplayMetrics
import android.view.Display
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowInsets
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import android.widget.Toast
import com.example.ia_jarvis.MainActivity
import com.example.ia_jarvis.touch.capture.ApercuCaptureTouch
import com.example.ia_jarvis.touch.capture.CaptureEcran
import com.example.ia_jarvis.touch.capture.CaptureTouch
import com.example.ia_jarvis.touch.capture.ServiceAccessibiliteJarvis
import kotlin.math.hypot
import kotlin.math.roundToInt

/**
 * Fenêtres superposées de JARVIS Touch : la bulle (toujours une seule),
 * son menu rapide, le mini-chat et l'aperçu des captures d'écran. Glisser déplace la bulle puis la range contre le bord
 * le plus proche ; toucher ouvre ou ferme le menu. La position (côté +
 * hauteur relative) est mémorisée sur l'appareil.
 */
class FenetresJarvisTouch(private val service: Context) {

    // Android 11+ : contexte de fenêtre dédié aux superpositions (mesures
    // d'écran à jour, pas d'accès « visuel » depuis le service).
    private val contexte: Context =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val ecran = service.getSystemService(DisplayManager::class.java)
                .getDisplay(Display.DEFAULT_DISPLAY)
            service.createDisplayContext(ecran)
                .createWindowContext(WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY, null)
        } else {
            service
        }

    private val wm = contexte.getSystemService(WindowManager::class.java)
    private val densite = contexte.resources.displayMetrics.density
    private val taille = (54 * densite).roundToInt()
    private val marge = (3 * densite).roundToInt()
    private val seuil = ViewConfiguration.get(contexte).scaledTouchSlop
    private val principal = Handler(Looper.getMainLooper())
    private val memoire = service.getSharedPreferences("jarvis_touch", Context.MODE_PRIVATE)

    private val rendu: RenduBulle = BulleJarvis(contexte)
    private val bulle: View get() = rendu.vue
    private val params = parametres(taille, taille)
    private var ajoutee = false

    private var menu: MenuJarvisTouch? = null
    private var chat: ChatJarvisTouch? = null
    private var fermeParExterieur = 0L

    // Capture d'écran (phase 3A) : au plus une, gardée tant qu'elle n'est
    // pas supprimée (Réduire la garde ; « Analyser l'écran » la rouvre).
    private var capture: CaptureTouch? = null
    private var apercu: ApercuCaptureTouch? = null
    private var ecranEteint: BroadcastReceiver? = null

    private var aDroite = memoire.getBoolean("droite", true)
    private var hauteur = memoire.getFloat("hauteur", 0.4f)
    private var rangement: ValueAnimator? = null

    private val estomper = Runnable {
        if (menu == null && chat == null && apercu == null) {
            bulle.animate().alpha(0.5f).setDuration(400).start()
            rendu.reposer()
        }
    }

    fun afficher() {
        placer()
        bulle.setOnTouchListener(Toucher())
        wm.addView(bulle, params)
        ajoutee = true
        eveiller()
    }

    fun retirer() {
        principal.removeCallbacksAndMessages(null)
        rangement?.cancel()
        fermerMenu()
        chat?.retirer()
        chat = null
        // JARVIS Touch arrêté : capture effacée, capture en cours ignorée.
        CaptureEcran.ecouteur = null
        fermerApercu(rendre = false)
        supprimerCapture()
        rendu.liberer()
        if (ajoutee) {
            try {
                wm.removeViewImmediate(bulle)
            } catch (_: Exception) {
            }
            ajoutee = false
        }
    }

    /** Rotation, changement de taille d'écran : même côté, même hauteur. */
    fun surChangementEcran() {
        fermerMenu()
        rangement?.cancel()
        // Mini-chat ouvert : refait aux nouvelles dimensions.
        if (chat != null) {
            fermerChat()
            principal.postDelayed({ if (ajoutee) ouvrirChat() }, 200)
        }
        // Aperçu : refait aux nouvelles dimensions (même capture).
        if (apercu != null) {
            fermerApercu(rendre = false)
            principal.postDelayed({ if (ajoutee && capture != null) montrerApercu() }, 200)
        }
        // Les mesures de l'écran sont mises à jour juste après.
        principal.postDelayed({
            if (!ajoutee) return@postDelayed
            placer()
            mettreAJour()
        }, 150)
    }

    // ── Position ────────────────────────────────────────────────────────

    /** Écran utilisable : hors barres système et encoche. */
    private fun zoneEcran(): Rect {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val mesures = wm.currentWindowMetrics
            val encarts = mesures.windowInsets.getInsetsIgnoringVisibility(
                WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout()
            )
            val b = mesures.bounds
            return Rect(encarts.left, encarts.top, b.width() - encarts.right, b.height() - encarts.bottom)
        }
        val dm = DisplayMetrics()
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getRealMetrics(dm)
        val haut = dimensionSysteme("status_bar_height")
        val bas = dimensionSysteme("navigation_bar_height")
        return Rect(0, haut, dm.widthPixels, dm.heightPixels - bas)
    }

    /** Plage autorisée pour le coin haut-gauche de la bulle. */
    private fun zone(): Rect {
        val e = zoneEcran()
        return Rect(e.left + marge, e.top + marge, e.right - taille - marge, e.bottom - taille - marge)
    }

    private fun dimensionSysteme(nom: String): Int {
        val id = contexte.resources.getIdentifier(nom, "dimen", "android")
        return if (id > 0) contexte.resources.getDimensionPixelSize(id) else 0
    }

    private fun placer() {
        val z = zone()
        params.x = if (aDroite) z.right else z.left
        params.y = (z.top + hauteur * (z.bottom - z.top).coerceAtLeast(0)).roundToInt()
    }

    private fun mettreAJour() {
        if (!ajoutee) return
        try {
            wm.updateViewLayout(bulle, params)
        } catch (_: Exception) {
        }
    }

    /** Fin du glissement : vers le bord le plus proche, en douceur. */
    private fun ranger() {
        val z = zone()
        aDroite = params.x + taille / 2 > (z.left + z.right + taille) / 2
        val cibleX = if (aDroite) z.right else z.left
        val cibleY = params.y.coerceIn(z.top, maxOf(z.top, z.bottom))
        hauteur = if (z.bottom > z.top) (cibleY - z.top).toFloat() / (z.bottom - z.top) else 0f
        memoire.edit().putBoolean("droite", aDroite).putFloat("hauteur", hauteur).apply()
        val departX = params.x
        val departY = params.y
        rangement = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 220
            interpolator = DecelerateInterpolator()
            addUpdateListener {
                val t = it.animatedValue as Float
                params.x = (departX + (cibleX - departX) * t).roundToInt()
                params.y = (departY + (cibleY - departY) * t).roundToInt()
                mettreAJour()
            }
            start()
        }
    }

    private fun eveiller() {
        principal.removeCallbacks(estomper)
        bulle.animate().cancel()
        bulle.alpha = 1f
        rendu.eveiller()
    }

    private fun planifierRepos() {
        principal.removeCallbacks(estomper)
        principal.postDelayed(estomper, 3000)
    }

    // ── Menu ────────────────────────────────────────────────────────────

    private fun basculerMenu() {
        if (menu != null) {
            fermerMenu()
        } else if (SystemClock.uptimeMillis() - fermeParExterieur > 350) {
            // (Le toucher sur la bulle vient de fermer le menu par
            // « l'extérieur » : ne pas le rouvrir aussitôt.)
            ouvrirMenu()
        }
    }

    private fun ouvrirMenu() {
        val m = MenuJarvisTouch(contexte, surFermer = {
            fermeParExterieur = SystemClock.uptimeMillis()
            fermerMenu()
        }, surDiscuter = { ouvrirChat() }, surAnalyserEcran = { analyserEcran() })
        val (largeur, haut) = m.mesurer()
        val z = zone()
        val ecart = (8 * densite).roundToInt()
        val p = parametres(largeur, WindowManager.LayoutParams.WRAP_CONTENT).apply {
            flags = flags or WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH
            x = if (aDroite) params.x - largeur - ecart else params.x + taille + ecart
            x = x.coerceIn(marge, maxOf(marge, z.right + taille - largeur))
            y = (params.y + taille / 2 - haut / 2).coerceIn(z.top, maxOf(z.top, z.bottom + taille - haut))
        }
        try {
            wm.addView(m.vue, p)
            menu = m
            m.apparaitre(depuisDroite = aDroite)
            eveiller()
        } catch (_: Exception) {
            m.liberer()
        }
    }

    private fun fermerMenu() {
        val m = menu ?: return
        menu = null
        m.liberer()
        try {
            wm.removeViewImmediate(m.vue)
        } catch (_: Exception) {
        }
        planifierRepos()
    }

    // ── Mini-chat ───────────────────────────────────────────────────────

    /** « Discuter » : la bulle laisse place au mini-chat (une seule fois). */
    private fun ouvrirChat() {
        fermerMenu()
        if (chat != null) return
        principal.removeCallbacks(estomper)
        val c = ChatJarvisTouch(
            contexte, wm, zoneEcran(),
            surReduire = { fermerChat() },
            surOuvrirJarvis = {
                fermerChat()
                ouvrirJarvis()
            },
        )
        try {
            c.afficher()
            chat = c
            bulle.visibility = View.GONE
            rendu.reposer()
        } catch (_: Exception) {
            c.retirer()
        }
    }

    /** Réduire : retour à la bulle ; la conversation (et une réponse en
     *  cours) continue dans JARVIS. */
    fun fermerChat() {
        val c = chat ?: return
        chat = null
        c.retirer()
        bulle.visibility = View.VISIBLE
        eveiller()
        planifierRepos()
    }

    // ── Capture d'écran ─────────────────────────────────────────────────

    /** « Analyser l'écran » : capture en attente → son aperçu ; sinon une
     *  nouvelle capture (consentement Android à chaque fois). */
    private fun analyserEcran() {
        fermerMenu()
        if (verrouille()) {
            informer("Déverrouillez le téléphone pour capturer l’écran.")
            return
        }
        if (capture != null) montrerApercu() else lancerCapture()
    }

    private fun lancerCapture() {
        if (CaptureEcran.enCours) return
        // La bulle ne doit pas figurer sur l'image : masquée jusqu'à l'issue.
        principal.removeCallbacks(estomper)
        bulle.visibility = View.INVISIBLE
        CaptureEcran.ecouteur = { surIssueCapture(it) }
        if (!CaptureEcran.demarrer(service)) {
            rendreBulle()
            informer("La capture d’écran n’a pas pu démarrer.")
        }
    }

    private fun surIssueCapture(issue: CaptureEcran.Issue) {
        when (issue) {
            is CaptureEcran.Issue.Reussie -> {
                supprimerCapture()
                capture = CaptureTouch(service, issue.image)
                montrerApercu()
            }
            is CaptureEcran.Issue.Echec -> {
                rendreBulle()
                informer(issue.message)
            }
            CaptureEcran.Issue.Annulee -> rendreBulle()
        }
    }

    private fun montrerApercu() {
        val c = capture ?: return rendreBulle()
        if (apercu != null) return
        val a = ApercuCaptureTouch(
            contexte, wm, zoneEcran(), c,
            surReduire = { fermerApercu() },
            // L'aperçu lâche l'image AVANT qu'elle soit libérée.
            surSupprimer = {
                fermerApercu()
                supprimerCapture()
            },
            surNouvelle = {
                fermerApercu(rendre = false)
                supprimerCapture()
                lancerCapture()
            },
            surActiverSansAutorisation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                !ServiceAccessibiliteJarvis.disponible
            ) {
                {
                    fermerApercu()
                    CaptureEcran.ouvrirReglagesAccessibilite(service)
                }
            } else {
                null
            },
        )
        try {
            a.afficher()
            apercu = a
            bulle.visibility = View.GONE
            rendu.reposer()
            surveillerEcranEteint(true)
        } catch (_: Exception) {
            a.retirer()
            rendreBulle()
            informer("L’aperçu de la capture n’a pas pu s’afficher.")
        }
    }

    private fun fermerApercu(rendre: Boolean = true) {
        val a = apercu
        apercu = null
        a?.retirer()
        surveillerEcranEteint(false)
        if (rendre) rendreBulle()
    }

    private fun supprimerCapture() {
        capture?.supprimer()
        capture = null
    }

    private fun rendreBulle() {
        if (!ajoutee || chat != null || apercu != null) return
        bulle.visibility = View.VISIBLE
        eveiller()
        planifierRepos()
    }

    /** Écran éteint (verrouillage) : l'aperçu se referme, jamais visible
     *  sur l'écran verrouillé. La capture reste jusqu'à « Supprimer ». */
    private fun surveillerEcranEteint(actif: Boolean) {
        if (actif && ecranEteint == null) {
            val r = object : BroadcastReceiver() {
                override fun onReceive(c: Context?, i: Intent?) {
                    if (apercu != null) fermerApercu()
                }
            }
            val filtre = IntentFilter(Intent.ACTION_SCREEN_OFF)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                service.registerReceiver(r, filtre, Context.RECEIVER_NOT_EXPORTED)
            } else {
                service.registerReceiver(r, filtre)
            }
            ecranEteint = r
        } else if (!actif) {
            val r = ecranEteint ?: return
            ecranEteint = null
            try {
                service.unregisterReceiver(r)
            } catch (_: Exception) {
            }
        }
    }

    private fun verrouille(): Boolean =
        service.getSystemService(KeyguardManager::class.java)?.isKeyguardLocked == true

    private fun informer(message: String) {
        Toast.makeText(service, message, Toast.LENGTH_LONG).show()
    }

    /** JARVIS au premier plan, sur la même conversation (même moteur). */
    private fun ouvrirJarvis() {
        try {
            service.startActivity(
                Intent(service, MainActivity::class.java).addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                )
            )
        } catch (_: Exception) {
        }
    }

    private fun parametres(largeur: Int, haut: Int): WindowManager.LayoutParams {
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        return WindowManager.LayoutParams(
            largeur, haut, type,
            // Jamais le focus (clavier des autres applis intact), et les
            // touchers hors de la fenêtre passent à l'application dessous.
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
    }

    // ── Gestes ──────────────────────────────────────────────────────────

    private inner class Toucher : View.OnTouchListener {
        private var departX = 0
        private var departY = 0
        private var doigtX = 0f
        private var doigtY = 0f
        private var glisse = false

        override fun onTouch(v: View, e: MotionEvent): Boolean {
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    rangement?.cancel()
                    eveiller()
                    departX = params.x
                    departY = params.y
                    doigtX = e.rawX
                    doigtY = e.rawY
                    glisse = false
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = e.rawX - doigtX
                    val dy = e.rawY - doigtY
                    if (!glisse && hypot(dx, dy) > seuil) {
                        glisse = true
                        fermerMenu()
                    }
                    if (glisse) {
                        val z = zone()
                        params.x = (departX + dx.roundToInt()).coerceIn(z.left, maxOf(z.left, z.right))
                        params.y = (departY + dy.roundToInt()).coerceIn(z.top, maxOf(z.top, z.bottom))
                        mettreAJour()
                    }
                }
                MotionEvent.ACTION_UP -> {
                    if (glisse) {
                        ranger()
                    } else {
                        v.performClick()
                        basculerMenu()
                    }
                    planifierRepos()
                }
                MotionEvent.ACTION_CANCEL -> {
                    if (glisse) ranger()
                    planifierRepos()
                }
            }
            return true
        }
    }
}
