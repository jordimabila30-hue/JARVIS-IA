package com.example.ia_jarvis.touch.capture

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.os.Build
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import com.example.ia_jarvis.R
import kotlin.math.roundToInt

/**
 * Éditeur de capture plein écran, ouvert dès la capture : l'image en grand,
 * la sélection active tout de suite ([RecadrageVue]) et une barre en haut :
 * Fermer (abandon : capture supprimée) · Annuler / Rétablir (visibles
 * seulement quand c'est possible) · Valider (recadrage appliqué, capture
 * gardée dans le cache privé pour une future utilisation).
 *
 * Historique : une entrée par geste complet (ou double-toucher), au plus
 * [MAX_HISTORIQUE] ; une nouvelle modification efface le « rétablir ».
 * Fenêtre sécurisée (FLAG_SECURE) : jamais dans les captures, les
 * enregistrements ni l'aperçu des récents. Rien n'est envoyé.
 */
class EditeurCaptureTouch(
    private val contexte: Context,
    private val wm: WindowManager,
    zoneEcran: Rect,
    private val capture: CaptureTouch,
    private val surFermer: () -> Unit,
    private val surValider: (Rect) -> Unit,
) {
    private companion object {
        const val MAX_HISTORIQUE = 30
        val FOND = Color.rgb(11, 10, 18)
        val ACCENT = Color.rgb(0x7A, 0x6C, 0xF0)
        const val MATCH = ViewGroup.LayoutParams.MATCH_PARENT
        const val WRAP = ViewGroup.LayoutParams.WRAP_CONTENT
    }

    private val densite = contexte.resources.displayMetrics.density
    private fun dp(v: Number) = (v.toFloat() * densite).roundToInt()

    private var ajoutee = false
    private val passe = ArrayDeque<RectF>()
    private val futur = ArrayDeque<RectF>()

    private val racine = object : FrameLayout(contexte) {
        override fun dispatchKeyEvent(event: KeyEvent): Boolean {
            if (event.keyCode == KeyEvent.KEYCODE_BACK) {
                if (event.action == KeyEvent.ACTION_UP) surFermer()
                return true
            }
            return super.dispatchKeyEvent(event)
        }
    }
    private val vue = RecadrageVue(contexte, capture.image)
    private val pilule = LinearLayout(contexte)
    private val annuler = bouton(R.drawable.touch_annuler, "Annuler la dernière modification", dp(48)) { annuler() }
    private val retablir = bouton(R.drawable.touch_retablir, "Rétablir la modification", dp(48)) { retablir() }

    // Zone utilisable (hors barres système) ; ce qui dépasse est assombri.
    private val params = WindowManager.LayoutParams(
        zoneEcran.width(), zoneEcran.height(),
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        },
        // Focalisable (touche Retour) ; aucun champ : le clavier ne s'ouvre pas.
        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
            WindowManager.LayoutParams.FLAG_DIM_BEHIND or
            WindowManager.LayoutParams.FLAG_SECURE or
            WindowManager.LayoutParams.FLAG_ALT_FOCUSABLE_IM,
        PixelFormat.OPAQUE,
    ).apply {
        gravity = Gravity.TOP or Gravity.START
        x = zoneEcran.left
        y = zoneEcran.top
        dimAmount = 0.85f
    }

    init {
        construire()
        vue.surModification = { avant, _ ->
            passe.addLast(avant)
            if (passe.size > MAX_HISTORIQUE) passe.removeFirst()
            futur.clear()
            majHistorique()
        }
        majHistorique()
    }

    fun afficher() {
        wm.addView(racine, params)
        ajoutee = true
        racine.alpha = 0f
        racine.animate().alpha(1f).setDuration(150).start()
    }

    /** Zone choisie, en pixels de la capture. */
    fun zoneChoisie(): Rect = vue.zoneChoisie()

    /** Fenêtre retirée : la vue lâche l'image (la capture est gardée ou
     *  supprimée par l'appelant, APRÈS ce retrait). */
    fun retirer() {
        if (!ajoutee) return
        ajoutee = false
        racine.animate().cancel()
        vue.surModification = null
        try {
            wm.removeViewImmediate(racine)
        } catch (_: Exception) {
        }
        racine.removeAllViews()
    }

    // ── Historique ──────────────────────────────────────────────────────

    private fun annuler() {
        val precedente = passe.removeLastOrNull() ?: return
        futur.addLast(RectF(vue.zoneChoisie()))
        vue.definir(precedente)
        majHistorique()
    }

    private fun retablir() {
        val suivante = futur.removeLastOrNull() ?: return
        passe.addLast(RectF(vue.zoneChoisie()))
        vue.definir(suivante)
        majHistorique()
    }

    private fun majHistorique() {
        annuler.visibility = if (passe.isEmpty()) View.GONE else View.VISIBLE
        retablir.visibility = if (futur.isEmpty()) View.GONE else View.VISIBLE
        pilule.visibility = if (passe.isEmpty() && futur.isEmpty()) View.INVISIBLE else View.VISIBLE
    }

    // ── Construction ────────────────────────────────────────────────────

    private fun construire() {
        racine.setBackgroundColor(FOND)
        val colonne = LinearLayout(contexte).apply { orientation = LinearLayout.VERTICAL }
        racine.addView(colonne, FrameLayout.LayoutParams(MATCH, MATCH))

        val barre = FrameLayout(contexte).apply { setPadding(dp(16), dp(12), dp(16), dp(8)) }
        barre.addView(
            bouton(R.drawable.touch_fermer, "Fermer et supprimer la capture", dp(52), contour = true) { surFermer() },
            FrameLayout.LayoutParams(dp(52), dp(52), Gravity.START or Gravity.CENTER_VERTICAL),
        )
        pilule.apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(dp(6), 0, dp(6), 0)
            background = GradientDrawable().apply {
                cornerRadius = dp(26).toFloat()
                setColor(Color.argb(30, 255, 255, 255))
                setStroke(dp(1), Color.argb(46, 255, 255, 255))
            }
            addView(annuler, LinearLayout.LayoutParams(dp(48), dp(48)))
            addView(retablir, LinearLayout.LayoutParams(dp(48), dp(48)))
        }
        barre.addView(pilule, FrameLayout.LayoutParams(WRAP, dp(52), Gravity.CENTER))
        barre.addView(
            bouton(R.drawable.touch_valider, "Valider le recadrage", dp(52), plein = true) {
                surValider(vue.zoneChoisie())
            },
            FrameLayout.LayoutParams(dp(52), dp(52), Gravity.END or Gravity.CENTER_VERTICAL),
        )
        colonne.addView(barre, LinearLayout.LayoutParams(MATCH, WRAP))
        colonne.addView(vue, LinearLayout.LayoutParams(MATCH, 0, 1f).apply { bottomMargin = dp(12) })
    }

    private fun bouton(
        icone: Int,
        description: String,
        taille: Int,
        contour: Boolean = false,
        plein: Boolean = false,
        action: () -> Unit,
    ) = ImageView(contexte).apply {
        setImageResource(icone)
        scaleType = ImageView.ScaleType.CENTER
        contentDescription = description
        val forme = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(if (plein) ACCENT else Color.TRANSPARENT)
            if (contour) setStroke(dp(1), Color.argb(70, 255, 255, 255))
        }
        background = RippleDrawable(
            ColorStateList.valueOf(Color.argb(60, 255, 255, 255)),
            forme,
            GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.WHITE)
            },
        )
        minimumWidth = taille
        minimumHeight = taille
        setOnClickListener { action() }
    }
}
