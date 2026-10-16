package com.example.ia_jarvis.touch

import android.animation.ValueAnimator
import android.content.Context
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
import kotlin.math.hypot
import kotlin.math.roundToInt

/**
 * Fenêtres superposées de JARVIS Touch : la bulle (toujours une seule) et
 * son menu rapide. Glisser déplace la bulle puis la range contre le bord
 * le plus proche ; toucher ouvre ou ferme le menu. La position (côté +
 * hauteur relative) est mémorisée sur l'appareil.
 */
class FenetresJarvisTouch(service: Context) {

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
    private var fermeParExterieur = 0L

    private var aDroite = memoire.getBoolean("droite", true)
    private var hauteur = memoire.getFloat("hauteur", 0.4f)
    private var rangement: ValueAnimator? = null

    private val estomper = Runnable {
        if (menu == null) {
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
        // Les mesures de l'écran sont mises à jour juste après.
        principal.postDelayed({
            if (!ajoutee) return@postDelayed
            placer()
            mettreAJour()
        }, 150)
    }

    // ── Position ────────────────────────────────────────────────────────

    /** Plage autorisée pour le coin haut-gauche de la bulle. */
    private fun zone(): Rect {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val mesures = wm.currentWindowMetrics
            val encarts = mesures.windowInsets.getInsetsIgnoringVisibility(
                WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout()
            )
            val b = mesures.bounds
            return Rect(
                encarts.left + marge,
                encarts.top + marge,
                b.width() - encarts.right - taille - marge,
                b.height() - encarts.bottom - taille - marge,
            )
        }
        val dm = DisplayMetrics()
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getRealMetrics(dm)
        val haut = dimensionSysteme("status_bar_height")
        val bas = dimensionSysteme("navigation_bar_height")
        return Rect(marge, haut + marge, dm.widthPixels - taille - marge, dm.heightPixels - bas - taille - marge)
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
        })
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
