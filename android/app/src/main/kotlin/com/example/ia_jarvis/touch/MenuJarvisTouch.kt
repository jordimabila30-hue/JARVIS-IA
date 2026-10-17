package com.example.ia_jarvis.touch

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.content.res.ColorStateList
import android.os.Handler
import android.os.Looper
import android.text.TextUtils
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import com.example.ia_jarvis.R
import kotlin.math.roundToInt

/**
 * Menu rapide de JARVIS Touch : quatre entrées en grille 2 × 2.
 * « Discuter » ouvre le mini-chat (phase 2) ; les autres annoncent
 * « Disponible prochainement » (aucun micro, aucune capture, aucun import).
 */
class MenuJarvisTouch(
    private val contexte: Context,
    private val surFermer: () -> Unit,
    private val surDiscuter: () -> Unit,
) {
    /** Entrées du menu (les actions réelles arriveront aux phases suivantes). */
    enum class Entree(val libelle: String, val icone: Int) {
        DISCUTER("Discuter", R.drawable.touch_discuter),
        VOCAL("Vocal", R.drawable.touch_vocal),
        ANALYSER_ECRAN("Analyser l’écran", R.drawable.touch_ecran),
        IMPORTER("Importer une conversation", R.drawable.touch_importer),
    }

    private val densite = contexte.resources.displayMetrics.density
    private fun dp(v: Number) = (v.toFloat() * densite).roundToInt()

    private val largeur = dp(240)
    private val principal = Handler(Looper.getMainLooper())
    private val statut = TextView(contexte)
    private val racine = LinearLayout(contexte)

    val vue: View get() = racine

    init {
        racine.orientation = LinearLayout.VERTICAL
        racine.setPadding(dp(12), dp(10), dp(12), dp(12))
        racine.background = GradientDrawable().apply {
            cornerRadius = dp(22).toFloat()
            setColor(Color.argb(232, 24, 22, 33))
            setStroke(dp(1), Color.argb(40, 255, 255, 255))
        }
        racine.elevation = dp(10).toFloat()
        // Toucher hors du menu (autre appli, bulle) : retour à la bulle.
        racine.setOnTouchListener { _, e ->
            if (e.actionMasked == MotionEvent.ACTION_OUTSIDE) {
                surFermer()
                true
            } else {
                false
            }
        }

        racine.addView(entete())
        val entrees = Entree.values()
        for (ligne in entrees.indices step 2) {
            val rang = LinearLayout(contexte).apply { orientation = LinearLayout.HORIZONTAL }
            for (entree in entrees.slice(ligne until minOf(ligne + 2, entrees.size))) {
                rang.addView(tuile(entree), LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            }
            racine.addView(rang)
        }
        statut.apply {
            setTextColor(Color.argb(230, 221, 213, 239))
            textSize = 12.5f
            gravity = Gravity.CENTER
            setPadding(0, dp(8), 0, 0)
            // Place réservée : la hauteur du menu ne change pas.
            text = "Disponible prochainement"
            visibility = View.INVISIBLE
        }
        racine.addView(statut)
    }

    /** Taille du menu avant son ajout (pour le placer à côté de la bulle). */
    fun mesurer(): Pair<Int, Int> {
        racine.measure(
            View.MeasureSpec.makeMeasureSpec(largeur, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
        )
        return largeur to racine.measuredHeight
    }

    fun apparaitre(depuisDroite: Boolean) {
        racine.pivotX = if (depuisDroite) largeur.toFloat() else 0f
        racine.pivotY = racine.measuredHeight / 2f
        racine.alpha = 0f
        racine.scaleX = 0.92f
        racine.scaleY = 0.92f
        racine.animate().alpha(1f).scaleX(1f).scaleY(1f).setDuration(160).start()
    }

    fun liberer() {
        principal.removeCallbacksAndMessages(null)
        racine.animate().cancel()
    }

    private fun entete(): View {
        val ligne = LinearLayout(contexte).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(6), 0, 0, dp(4))
        }
        ligne.addView(TextView(contexte).apply {
            text = "JARVIS"
            letterSpacing = 0.18f
            textSize = 12f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            setTextColor(Color.argb(200, 221, 213, 239))
        }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        ligne.addView(TextView(contexte).apply {
            text = "✕"
            textSize = 15f
            gravity = Gravity.CENTER
            setTextColor(Color.argb(170, 255, 255, 255))
            contentDescription = "Fermer le menu"
            background = ondulation(dp(16).toFloat())
            setOnClickListener { surFermer() }
        }, LinearLayout.LayoutParams(dp(32), dp(32)))
        return ligne
    }

    private fun tuile(entree: Entree): View {
        val colonne = LinearLayout(contexte).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(4), dp(8), dp(4), dp(8))
            background = ondulation(dp(16).toFloat())
            contentDescription = entree.libelle
            setOnClickListener {
                if (entree == Entree.DISCUTER) surDiscuter() else annoncer(entree)
            }
        }
        val pastille = FrameLayout(contexte).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.argb(38, 140, 122, 210))
                setStroke(dp(1), Color.argb(70, 140, 122, 210))
            }
        }
        pastille.addView(ImageView(contexte).apply {
            setImageResource(entree.icone)
        }, FrameLayout.LayoutParams(dp(22), dp(22), Gravity.CENTER))
        colonne.addView(pastille, LinearLayout.LayoutParams(dp(46), dp(46)))
        colonne.addView(TextView(contexte).apply {
            text = entree.libelle
            textSize = 12f
            gravity = Gravity.CENTER
            maxLines = 2
            ellipsize = TextUtils.TruncateAt.END
            setTextColor(Color.argb(235, 255, 255, 255))
            setPadding(0, dp(6), 0, 0)
        })
        return colonne
    }

    /** Phase 1 : rien n'est déclenché, on l'annonce simplement. */
    private fun annoncer(entree: Entree) {
        statut.text = "Disponible prochainement"
        statut.visibility = View.VISIBLE
        principal.removeCallbacksAndMessages(null)
        principal.postDelayed({ statut.visibility = View.INVISIBLE }, 2200)
    }

    private fun ondulation(rayon: Float) = RippleDrawable(
        ColorStateList.valueOf(Color.argb(50, 255, 255, 255)),
        null,
        GradientDrawable().apply {
            cornerRadius = rayon
            setColor(Color.WHITE)
        },
    )
}
