package com.example.ia_jarvis.touch

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import com.example.ia_jarvis.R
import kotlin.math.roundToInt

/**
 * Menu rapide de JARVIS Touch (esprit AssistiveTouch) : panneau sombre
 * translucide aux coins très arrondis, quatre actions en grille 2 × 2
 * séparées par de fins traits. « Discuter » ouvre le mini-chat, « Capturer »
 * la capture d'écran ; « Vocal » et « Importer » annoncent « Disponible
 * prochainement » dans l'en-tête. Rendu natif léger : aucun flou, une seule
 * ombre, une animation courte à l'ouverture.
 */
class MenuJarvisTouch(
    private val contexte: Context,
    private val surFermer: () -> Unit,
    private val surDiscuter: () -> Unit,
    private val surCapturer: () -> Unit,
) {
    /** Entrées du menu (les actions réelles arrivent phase par phase). */
    enum class Entree(val libelle: String, val icone: Int) {
        DISCUTER("Discuter", R.drawable.touch_discuter),
        VOCAL("Vocal", R.drawable.touch_vocal),
        CAPTURER("Capturer", R.drawable.touch_ecran),
        IMPORTER("Importer", R.drawable.touch_importer),
    }

    private companion object {
        val TRAIT = Color.argb(30, 255, 255, 255)
        val TEXTE = Color.argb(240, 255, 255, 255)
        val TITRE = Color.argb(215, 221, 213, 239)
    }

    private val densite = contexte.resources.displayMetrics.density
    private fun dp(v: Number) = (v.toFloat() * densite).roundToInt()

    private val largeur = dp(264)
    private val principal = Handler(Looper.getMainLooper())
    private val titre = TextView(contexte)
    private val racine = LinearLayout(contexte)

    val vue: View get() = racine

    init {
        racine.orientation = LinearLayout.VERTICAL
        racine.setPadding(dp(14), dp(10), dp(14), dp(14))
        racine.background = GradientDrawable(
            GradientDrawable.Orientation.TOP_BOTTOM,
            intArrayOf(Color.argb(246, 38, 32, 64), Color.argb(248, 20, 18, 34)),
        ).apply {
            cornerRadius = dp(30).toFloat()
            setStroke(dp(1), Color.argb(80, 150, 132, 255))
        }
        racine.elevation = dp(12).toFloat()
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
            if (ligne > 0) racine.addView(trait(horizontal = true))
            val rang = LinearLayout(contexte).apply { orientation = LinearLayout.HORIZONTAL }
            entrees.slice(ligne until minOf(ligne + 2, entrees.size)).forEachIndexed { i, entree ->
                if (i > 0) rang.addView(trait(horizontal = false))
                rang.addView(tuile(entree), LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            }
            racine.addView(rang)
        }
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
        racine.scaleX = 0.9f
        racine.scaleY = 0.9f
        racine.animate().alpha(1f).scaleX(1f).scaleY(1f)
            .setInterpolator(DecelerateInterpolator(1.6f)).setDuration(170).start()
    }

    fun liberer() {
        principal.removeCallbacksAndMessages(null)
        racine.animate().cancel()
    }

    private fun entete(): View {
        val ligne = LinearLayout(contexte).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(10), 0, 0, dp(6))
        }
        titre.apply {
            text = "JARVIS"
            letterSpacing = 0.22f
            textSize = 12.5f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            setTextColor(TITRE)
            maxLines = 1
        }
        ligne.addView(titre, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        ligne.addView(TextView(contexte).apply {
            text = "✕"
            textSize = 15f
            gravity = Gravity.CENTER
            setTextColor(Color.argb(180, 255, 255, 255))
            contentDescription = "Fermer le menu"
            background = ondulation(GradientDrawable.OVAL)
            setOnClickListener { surFermer() }
        }, LinearLayout.LayoutParams(dp(36), dp(36)))
        return ligne
    }

    private fun trait(horizontal: Boolean) = View(contexte).apply {
        setBackgroundColor(TRAIT)
        layoutParams = if (horizontal) {
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(1)).apply {
                leftMargin = dp(10)
                rightMargin = dp(10)
            }
        } else {
            LinearLayout.LayoutParams(dp(1), ViewGroup.LayoutParams.MATCH_PARENT).apply {
                topMargin = dp(10)
                bottomMargin = dp(10)
            }
        }
    }

    private fun tuile(entree: Entree): View {
        val colonne = LinearLayout(contexte).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(4), dp(12), dp(4), dp(12))
            background = ondulation(GradientDrawable.RECTANGLE)
            contentDescription = entree.libelle
            setOnClickListener {
                when (entree) {
                    Entree.DISCUTER -> surDiscuter()
                    Entree.CAPTURER -> surCapturer()
                    else -> annoncer()
                }
            }
        }
        val pastille = FrameLayout(contexte).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.argb(46, 122, 108, 240))
                setStroke(dp(1), Color.argb(120, 150, 135, 255))
            }
        }
        pastille.addView(ImageView(contexte).apply {
            setImageResource(entree.icone)
        }, FrameLayout.LayoutParams(dp(25), dp(25), Gravity.CENTER))
        colonne.addView(pastille, LinearLayout.LayoutParams(dp(56), dp(56)))
        colonne.addView(TextView(contexte).apply {
            text = entree.libelle
            textSize = 13.5f
            gravity = Gravity.CENTER
            maxLines = 1
            setTextColor(TEXTE)
            setPadding(0, dp(8), 0, 0)
        })
        return colonne
    }

    /** Vocal / Importer : rien n'est déclenché, l'en-tête l'annonce. */
    private fun annoncer() {
        titre.letterSpacing = 0f
        titre.text = "Disponible prochainement"
        principal.removeCallbacksAndMessages(null)
        principal.postDelayed({
            titre.letterSpacing = 0.22f
            titre.text = "JARVIS"
        }, 2200)
    }

    private fun ondulation(forme: Int) = RippleDrawable(
        ColorStateList.valueOf(Color.argb(45, 255, 255, 255)),
        null,
        GradientDrawable().apply {
            shape = forme
            cornerRadius = dp(20).toFloat()
            setColor(Color.WHITE)
        },
    )
}
