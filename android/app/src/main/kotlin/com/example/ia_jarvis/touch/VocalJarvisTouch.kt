package com.example.ia_jarvis.touch

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.animation.LinearInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import com.example.ia_jarvis.R
import kotlin.math.PI
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * Vocal flottant de JARVIS Touch : petite fenêtre en haut de l'écran qui
 * pilote LA session vocale de l'application (côté Dart :
 * `PasserelleVocalTouch`, même reconnaissance, même voix, même
 * conversation). Pas de particules PIM : un cercle sombre et le symbole
 * audio bleu, animé selon l'état et le niveau réel.
 *
 * Micro : couper / réactiver l'écoute. Chat : mini-chat écrit, même
 * conversation. Réduire : la session continue (bulle marquée, un toucher
 * la rouvre). Quitter : fin réelle, micro et voix libérés.
 */
class VocalJarvisTouch(
    private val contexte: Context,
    private val wm: WindowManager,
    zone: Rect,
    private val surReduire: () -> Unit,
    private val surChat: () -> Unit,
    private val surQuitter: () -> Unit,
) {
    private companion object {
        val TEXTE = Color.argb(240, 255, 255, 255)
        val SECONDAIRE = Color.argb(170, 221, 213, 239)
        val ERREUR = Color.rgb(0xF2, 0x9A, 0x8C)
    }

    private val densite = contexte.resources.displayMetrics.density
    private fun dp(v: Number) = (v.toFloat() * densite).roundToInt()

    private val racine = LinearLayout(contexte)
    private val symbole = SymboleAudio(contexte)
    private val etatTexte = TextView(contexte)
    private val phrase = TextView(contexte)
    private val micro = ImageView(contexte)
    private val libelleMicro = TextView(contexte)
    private var ajoutee = false
    private var actif = false

    private val largeur = minOf(zone.width() - dp(24), dp(320))
    private val params = WindowManager.LayoutParams(
        largeur, WindowManager.LayoutParams.WRAP_CONTENT,
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        },
        // Jamais le focus (clavier des autres applis intact) ; touchers
        // hors de la fenêtre : à l'application de dessous.
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
        PixelFormat.TRANSLUCENT,
    ).apply {
        gravity = Gravity.TOP or Gravity.START
        x = zone.left + (zone.width() - largeur) / 2
        y = zone.top + dp(12)
    }

    init {
        construire()
    }

    fun afficher() {
        wm.addView(racine, params)
        ajoutee = true
        racine.alpha = 0f
        racine.animate().alpha(1f).setDuration(150).start()
    }

    fun retirer() {
        if (!ajoutee) return
        ajoutee = false
        symbole.arreter()
        racine.animate().cancel()
        try {
            wm.removeViewImmediate(racine)
        } catch (_: Exception) {
        }
    }

    /** État envoyé par Dart (`vocal`). */
    fun appliquer(e: Map<*, *>) {
        actif = e["actif"] == true
        val probleme = e["probleme"] as? String
        val etat = if (actif) e["etat"] as? String ?: "repos" else "coupe"
        symbole.changer(etat)
        etatTexte.setTextColor(if (probleme != null) ERREUR else TEXTE)
        etatTexte.text = probleme ?: when (etat) {
            "ecoute" -> "J’écoute…"
            "reflexion" -> "Je réfléchis…"
            "parole" -> "Je réponds…"
            "coupe" -> "Micro coupé"
            else -> (e["statut"] as? String)?.takeIf { it.isNotBlank() } ?: "Prêt"
        }
        val reponse = e["reponse"] as? String
        val entendu = e["transcription"] as? String
        phrase.text = when {
            etat == "parole" && !reponse.isNullOrBlank() -> reponse
            !entendu.isNullOrBlank() -> "« $entendu »"
            else -> ""
        }
        phrase.visibility = if (phrase.text.isNullOrEmpty()) View.GONE else View.VISIBLE
        micro.alpha = if (actif) 1f else 0.45f
        libelleMicro.text = if (actif) "Micro" else "Micro coupé"
    }

    /** Amplitude réelle (0 à 1) du micro ou de la voix de JARVIS. */
    fun niveau(n: Double) = symbole.niveau(n.toFloat())

    // ── Construction ────────────────────────────────────────────────────

    private fun construire() {
        racine.orientation = LinearLayout.VERTICAL
        racine.gravity = Gravity.CENTER_HORIZONTAL
        racine.setPadding(dp(16), dp(10), dp(10), dp(14))
        racine.background = GradientDrawable(
            GradientDrawable.Orientation.TOP_BOTTOM,
            intArrayOf(Color.argb(246, 38, 32, 64), Color.argb(248, 20, 18, 34)),
        ).apply {
            cornerRadius = dp(26).toFloat()
            setStroke(dp(1), Color.argb(80, 150, 132, 255))
        }
        racine.elevation = dp(12).toFloat()

        val entete = LinearLayout(contexte).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        entete.addView(TextView(contexte).apply {
            text = "JARVIS — Vocal"
            textSize = 13f
            letterSpacing = 0.06f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            setTextColor(SECONDAIRE)
        }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        entete.addView(TextView(contexte).apply {
            text = "—"
            textSize = 16f
            gravity = Gravity.CENTER
            setTextColor(TEXTE)
            contentDescription = "Réduire (la session vocale continue)"
            setOnClickListener { surReduire() }
        }, LinearLayout.LayoutParams(dp(40), dp(36)))
        racine.addView(entete, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        racine.addView(symbole, LinearLayout.LayoutParams(dp(92), dp(92)).apply { topMargin = dp(4) })
        etatTexte.apply {
            textSize = 15f
            gravity = Gravity.CENTER
            setTextColor(TEXTE)
            text = "Préparation…"
        }
        racine.addView(etatTexte, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = dp(8) })
        phrase.apply {
            textSize = 12.5f
            gravity = Gravity.CENTER
            setTextColor(SECONDAIRE)
            maxLines = 2
            ellipsize = TextUtils.TruncateAt.END
            visibility = View.GONE
            setPadding(dp(8), dp(4), dp(8), 0)
        }
        racine.addView(phrase, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        val commandes = LinearLayout(contexte).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(0, dp(12), 0, 0)
        }
        commandes.addView(commande(micro, libelleMicro, R.drawable.touch_vocal, "Micro", "Couper ou réactiver l’écoute") {
            CanalMiniChat.appeler("vocalMicro", null, { e -> (e as? Map<*, *>)?.let { appliquer(it) } }, {})
        })
        commandes.addView(commande(ImageView(contexte), TextView(contexte), R.drawable.touch_discuter, "Chat", "Revenir au chat écrit") { surChat() })
        commandes.addView(commande(ImageView(contexte), TextView(contexte), R.drawable.touch_fermer, "Quitter", "Quitter le vocal (micro coupé)") { surQuitter() })
        racine.addView(commandes, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
    }

    private fun commande(
        icone: ImageView,
        libelle: TextView,
        dessin: Int,
        texte: String,
        description: String,
        action: () -> Unit,
    ): View {
        val colonne = LinearLayout(contexte).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            contentDescription = description
            setOnClickListener { action() }
            setPadding(dp(6), dp(2), dp(6), dp(2))
        }
        val pastille = FrameLayout(contexte).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.argb(46, 122, 108, 240))
                setStroke(dp(1), Color.argb(120, 150, 135, 255))
            }
        }
        icone.setImageResource(dessin)
        pastille.addView(icone, FrameLayout.LayoutParams(dp(22), dp(22), Gravity.CENTER))
        colonne.addView(pastille, LinearLayout.LayoutParams(dp(48), dp(48)))
        libelle.apply {
            text = texte
            textSize = 12f
            gravity = Gravity.CENTER
            setTextColor(TEXTE)
            setPadding(0, dp(5), 0, 0)
        }
        colonne.addView(libelle)
        return colonne.also {
            it.layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        }
    }

    /**
     * Cercle sombre + symbole audio bleu (5 barres claires). UNE animation,
     * active seulement hors repos et tant que la vue est affichée.
     * Écoute / parole : barres suivant le niveau réel ; réflexion : vague
     * lente (aucun son simulé) ; repos / micro coupé : immobile.
     */
    private class SymboleAudio(context: Context) : View(context) {
        private val d = resources.displayMetrics.density
        private val fond = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(0x1E, 0x20, 0x30) }
        private val anneau = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = d
            color = Color.argb(70, 142, 162, 255)
        }
        private val disque = Paint(Paint.ANTI_ALIAS_FLAG)
        private val barre = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(0xFF, 0xFD, 0xF9) }
        private val r = RectF()
        private val profil = floatArrayOf(0.45f, 0.7f, 1f, 0.7f, 0.45f)
        private var etat = "repos"
        private var niveau = 0f
        private var cible = 0f
        private var t = 0f
        private val anim = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 1000
            repeatCount = ValueAnimator.INFINITE
            interpolator = LinearInterpolator()
            addUpdateListener {
                t = it.animatedFraction
                // Lissage : montée vive, descente douce.
                niveau += (cible - niveau) * (if (cible > niveau) 0.5f else 0.12f)
                invalidate()
            }
        }

        fun changer(e: String) {
            if (e == etat) return
            etat = e
            if (e == "repos" || e == "coupe") {
                anim.cancel()
                niveau = 0f
                cible = 0f
                invalidate()
            } else if (isAttachedToWindow && !anim.isStarted) {
                anim.start()
            }
        }

        fun niveau(n: Float) {
            cible = n.coerceIn(0f, 1f)
        }

        fun arreter() = anim.cancel()

        override fun onAttachedToWindow() {
            super.onAttachedToWindow()
            if (etat != "repos" && etat != "coupe") anim.start()
        }

        override fun onDetachedFromWindow() {
            anim.cancel()
            super.onDetachedFromWindow()
        }

        override fun onSizeChanged(w: Int, h: Int, ow: Int, oh: Int) {
            val rd = minOf(w, h) * 0.33f
            disque.shader = LinearGradient(
                w / 2f - rd, h / 2f - rd, w / 2f + rd, h / 2f + rd,
                Color.rgb(0x7D, 0x8D, 0xF5), Color.rgb(0x4C, 0x55, 0xC4), Shader.TileMode.CLAMP,
            )
        }

        override fun onDraw(c: Canvas) {
            val cx = width / 2f
            val cy = height / 2f
            val rayon = minOf(width, height) / 2f
            c.drawCircle(cx, cy, rayon - d, fond)
            c.drawCircle(cx, cy, rayon - d, anneau)
            val rd = rayon * 0.66f
            c.drawCircle(cx, cy, rd, disque)
            val lb = rd * 0.13f
            val ecart = rd * 0.1f
            val total = 5 * lb + 4 * ecart
            for (i in 0 until 5) {
                val force = when (etat) {
                    "ecoute", "parole" -> {
                        val vague = 0.5f + 0.5f * sin((t * 2 * PI + i * 1.1).toFloat())
                        // Niveau réel ; sans niveau (voix sans mesure), petite onde liée à l'état.
                        val base = if (niveau > 0.03f) niveau else if (etat == "parole") 0.35f else 0.08f
                        0.25f + 0.75f * base * (0.55f + 0.45f * vague)
                    }
                    "reflexion" -> 0.3f + 0.2f * (0.5f + 0.5f * sin((t * 2 * PI - i * 0.7).toFloat()))
                    else -> 0.35f
                }
                val h = max(lb, rd * 1.1f * force * profil[i])
                val x = cx - total / 2 + i * (lb + ecart)
                r.set(x, cy - h / 2, x + lb, cy + h / 2)
                c.drawRoundRect(r, lb / 2, lb / 2, barre)
            }
        }
    }
}
