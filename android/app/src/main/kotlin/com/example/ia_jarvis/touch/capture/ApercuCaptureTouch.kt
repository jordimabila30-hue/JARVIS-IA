package com.example.ia_jarvis.touch.capture

import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.view.Gravity
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import com.example.ia_jarvis.R
import kotlin.math.roundToInt

/**
 * Aperçu d'une capture dans JARVIS Touch (sans ouvrir JARVIS) : l'image,
 * « Recadrer », « Supprimer », « Nouvelle » et Réduire (la capture reste
 * disponible, « Analyser l'écran » la rouvre). Mode recadrage dans la même
 * fenêtre ([RecadrageVue]) : Annuler / Tout / Valider.
 *
 * Fenêtre sécurisée (FLAG_SECURE) : jamais dans les captures, les
 * enregistrements ni l'aperçu des récents. Rien n'est envoyé.
 */
class ApercuCaptureTouch(
    private val contexte: Context,
    private val wm: WindowManager,
    private val zoneEcran: Rect,
    private val capture: CaptureTouch,
    private val surReduire: () -> Unit,
    private val surSupprimer: () -> Unit,
    private val surNouvelle: () -> Unit,
    /** Service d'accessibilité absent : proposer de l'activer (null : rien). */
    private val surActiverSansAutorisation: (() -> Unit)?,
) {
    private companion object {
        val IVOIRE = Color.rgb(0xFF, 0xFD, 0xF9)
        val FOND_IMAGE = Color.rgb(0xF1, 0xEE, 0xE8)
        val TRAIT = Color.rgb(0xDC, 0xD3, 0xC4)
        val SIGNAL = Color.rgb(0x55, 0x59, 0xB8)
        val TEXTE = Color.rgb(0x27, 0x29, 0x32)
        val SECONDAIRE = Color.rgb(0x6F, 0x6A, 0x72)
        val ERREUR = Color.rgb(0xA6, 0x3D, 0x40)
        const val MATCH = ViewGroup.LayoutParams.MATCH_PARENT
        const val WRAP = ViewGroup.LayoutParams.WRAP_CONTENT
    }

    private val densite = contexte.resources.displayMetrics.density
    private fun dp(v: Number) = (v.toFloat() * densite).roundToInt()

    private var ajoutee = false
    private var recadrage: RecadrageVue? = null

    private val racine = object : FrameLayout(contexte) {
        override fun dispatchKeyEvent(event: KeyEvent): Boolean {
            if (event.keyCode == KeyEvent.KEYCODE_BACK) {
                if (event.action == KeyEvent.ACTION_UP) {
                    if (recadrage != null) quitterRecadrage() else surReduire()
                }
                return true
            }
            return super.dispatchKeyEvent(event)
        }

        // Fenêtre modale de la taille de la carte : les touchers hors d'elle
        // arrivent ici (hors des limites) = réduire.
        override fun dispatchTouchEvent(e: MotionEvent): Boolean {
            if (e.actionMasked == MotionEvent.ACTION_DOWN &&
                (e.x < 0 || e.y < 0 || e.x > width || e.y > height)
            ) {
                if (recadrage == null) surReduire()
                return true
            }
            return super.dispatchTouchEvent(e)
        }
    }
    private val sousTitre = TextView(contexte)
    private val centre = FrameLayout(contexte)
    private val vueImage = ImageView(contexte)
    private val statut = TextView(contexte)
    private val pied = LinearLayout(contexte)

    // Carte placée comme la bulle : coordonnées d'écran, dans la zone
    // utilisable (hors barres système). Voile : celui du système (dim).
    private val largeur = minOf(zoneEcran.width() - dp(24), dp(460))
    private val hauteur = minOf(zoneEcran.height() - dp(28), dp(860))
    private val params = WindowManager.LayoutParams(
        largeur, hauteur,
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
        PixelFormat.TRANSLUCENT,
    ).apply {
        gravity = Gravity.TOP or Gravity.START
        x = zoneEcran.left + (zoneEcran.width() - largeur) / 2
        y = zoneEcran.top + (zoneEcran.height() - hauteur) / 2
        dimAmount = 0.45f
    }

    init {
        construire()
        montrerImage()
    }

    fun afficher() {
        wm.addView(racine, params)
        ajoutee = true
        racine.alpha = 0f
        racine.animate().alpha(1f).setDuration(140).start()
    }

    /** Fenêtre retirée ; l'image est lâchée (la capture, elle, est gardée
     *  ou supprimée par l'appelant). */
    fun retirer() {
        if (!ajoutee) return
        ajoutee = false
        racine.animate().cancel()
        vueImage.setImageDrawable(null)
        recadrage?.let { centre.removeView(it) }
        recadrage = null
        try {
            wm.removeViewImmediate(racine)
        } catch (_: Exception) {
        }
    }

    // ── Construction ────────────────────────────────────────────────────

    private fun construire() {
        val carte = LinearLayout(contexte).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable().apply {
                cornerRadius = dp(22).toFloat()
                setColor(IVOIRE)
                setStroke(dp(1), TRAIT)
            }
            clipToOutline = true
        }
        racine.addView(carte, FrameLayout.LayoutParams(MATCH, MATCH))

        carte.addView(entete(), LinearLayout.LayoutParams(MATCH, WRAP))
        carte.addView(View(contexte).apply { setBackgroundColor(TRAIT) }, LinearLayout.LayoutParams(MATCH, 1))

        centre.setBackgroundColor(FOND_IMAGE)
        vueImage.scaleType = ImageView.ScaleType.FIT_CENTER
        vueImage.contentDescription = "Capture d’écran"
        centre.addView(vueImage, FrameLayout.LayoutParams(MATCH, MATCH).apply {
            setMargins(dp(10), dp(10), dp(10), dp(10))
        })
        carte.addView(centre, LinearLayout.LayoutParams(MATCH, 0, 1f))

        statut.apply {
            textSize = 12f
            setTextColor(SECONDAIRE)
            gravity = Gravity.CENTER
            setPadding(dp(14), dp(8), dp(14), 0)
        }
        carte.addView(statut, LinearLayout.LayoutParams(MATCH, WRAP))
        surActiverSansAutorisation?.let { activer ->
            carte.addView(texteBouton(
                "Ne plus demander l’autorisation à chaque capture", SIGNAL,
                "Ouvrir Paramètres › Accessibilité pour activer JARVIS Touch",
            ) { activer() }.apply { textSize = 12.5f }, LinearLayout.LayoutParams(MATCH, WRAP))
        }

        pied.orientation = LinearLayout.HORIZONTAL
        pied.gravity = Gravity.CENTER_VERTICAL
        pied.setPadding(dp(10), dp(8), dp(10), dp(12))
        carte.addView(pied, LinearLayout.LayoutParams(MATCH, WRAP))
    }

    private fun entete(): View {
        val ligne = LinearLayout(contexte).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16), dp(10), dp(6), dp(10))
        }
        ligne.addView(View(contexte).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(SIGNAL)
            }
        }, LinearLayout.LayoutParams(dp(9), dp(9)).apply { marginEnd = dp(10) })
        val textes = LinearLayout(contexte).apply { orientation = LinearLayout.VERTICAL }
        textes.addView(TextView(contexte).apply {
            text = "Capture d’écran"
            textSize = 15f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            setTextColor(TEXTE)
        })
        sousTitre.apply {
            textSize = 11.5f
            setTextColor(SECONDAIRE)
        }
        textes.addView(sousTitre)
        ligne.addView(textes, LinearLayout.LayoutParams(0, WRAP, 1f))
        ligne.addView(texteBouton("Nouvelle", SIGNAL, "Nouvelle capture (celle-ci est supprimée)") { surNouvelle() })
        ligne.addView(ImageView(contexte).apply {
            setImageResource(R.drawable.touch_reduire)
            scaleType = ImageView.ScaleType.CENTER
            contentDescription = "Réduire (la capture reste disponible)"
            background = ondulation()
            setOnClickListener { surReduire() }
        }, LinearLayout.LayoutParams(dp(44), dp(44)))
        return ligne
    }

    // ── Modes ───────────────────────────────────────────────────────────

    private fun montrerImage() {
        val image = capture.actuelle
        vueImage.setImageBitmap(image)
        vueImage.visibility = View.VISIBLE
        sousTitre.text = "${image.width} × ${image.height} px" +
            (if (capture.recadrageApplique) " · recadrée" else "") + " · locale et temporaire"
        statut.setTextColor(SECONDAIRE)
        statut.text = "Gardée sur ce téléphone, jamais envoyée. « Supprimer » l’efface."
        pied.removeAllViews()
        pied.addView(capsule("Supprimer", ERREUR, plein = false) { surSupprimer() }, poids())
        if (capture.recadrageApplique) {
            pied.addView(capsule("Annuler le recadrage", TEXTE, plein = false) { annulerRecadrage() }, poids(1.4f))
        }
        pied.addView(capsule("Recadrer", SIGNAL, plein = true) { entrerRecadrage() }, poids())
    }

    private fun entrerRecadrage() {
        if (capture.originale.isRecycled) return
        // Toujours sur l'image d'origine, zone précédente reprise.
        val vue = RecadrageVue(contexte, capture.originale, capture.zone)
        vueImage.setImageDrawable(null)
        vueImage.visibility = View.GONE
        centre.addView(vue, FrameLayout.LayoutParams(MATCH, MATCH))
        recadrage = vue
        sousTitre.text = "Recadrer · ${capture.originale.width} × ${capture.originale.height} px"
        statut.setTextColor(SECONDAIRE)
        statut.text = "Ajustez les coins ou les bords ; glissez la zone pour la déplacer."
        pied.removeAllViews()
        pied.addView(capsule("Annuler", TEXTE, plein = false) { quitterRecadrage() }, poids())
        pied.addView(capsule("Tout", TEXTE, plein = false) { vue.toutSelectionner() }, poids(0.8f))
        pied.addView(capsule("Valider", SIGNAL, plein = true) { validerRecadrage() }, poids())
    }

    private fun quitterRecadrage() {
        recadrage?.let { centre.removeView(it) }
        recadrage = null
        montrerImage()
    }

    private fun validerRecadrage() {
        val vue = recadrage ?: return
        val z = vue.zoneChoisie()
        val ok = capture.recadrer(z)
        centre.removeView(vue)
        recadrage = null
        montrerImage()
        if (!ok) {
            statut.setTextColor(ERREUR)
            statut.text = "Le recadrage n’a pas pu être fait (mémoire insuffisante). L’image n’a pas changé."
        }
    }

    private fun annulerRecadrage() {
        // L'image recadrée est lâchée par la vue AVANT d'être libérée.
        vueImage.setImageDrawable(null)
        capture.annulerRecadrage()
        montrerImage()
    }

    // ── Petits éléments ─────────────────────────────────────────────────

    private fun poids(p: Float = 1f) = LinearLayout.LayoutParams(0, dp(44), p).apply {
        marginStart = dp(4)
        marginEnd = dp(4)
    }

    private fun capsule(libelle: String, couleur: Int, plein: Boolean, action: () -> Unit) =
        TextView(contexte).apply {
            text = libelle
            textSize = 13.5f
            gravity = Gravity.CENTER
            maxLines = 1
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            setTextColor(if (plein) Color.WHITE else couleur)
            background = android.graphics.drawable.RippleDrawable(
                android.content.res.ColorStateList.valueOf(Color.argb(50, 85, 89, 184)),
                GradientDrawable().apply {
                    cornerRadius = dp(22).toFloat()
                    if (plein) setColor(couleur) else {
                        setColor(Color.TRANSPARENT)
                        setStroke(dp(1), TRAIT)
                    }
                },
                GradientDrawable().apply {
                    cornerRadius = dp(22).toFloat()
                    setColor(Color.WHITE)
                },
            )
            setOnClickListener { action() }
        }

    private fun texteBouton(libelle: String, couleur: Int, description: String, action: () -> Unit) =
        TextView(contexte).apply {
            text = libelle
            textSize = 13f
            setTextColor(couleur)
            gravity = Gravity.CENTER
            setPadding(dp(10), dp(10), dp(10), dp(10))
            contentDescription = description
            background = ondulation()
            setOnClickListener { action() }
        }

    private fun ondulation() = android.graphics.drawable.RippleDrawable(
        android.content.res.ColorStateList.valueOf(Color.argb(40, 85, 89, 184)),
        null,
        GradientDrawable().apply {
            cornerRadius = dp(22).toFloat()
            setColor(Color.WHITE)
        },
    )
}
